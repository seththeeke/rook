import Foundation
import Observation
import RookFormatting
import RookLiveActivityKit
import RookModels
import RookNetworking
import RookSession

/// Starts, updates and ends the workout Live Activity (ActivityKit in the app; a fake in tests).
public protocol LiveActivityControlling: Sendable {
    func start(workoutId: String, state: WorkoutActivityAttributes.ContentState) async
    func update(workoutId: String, state: WorkoutActivityAttributes.ContentState) async
    func end(workoutId: String) async
    /// Ends every activity except the given workout's (cleans up after a force-quit).
    func endAll(except workoutId: String?) async
    /// Whether an activity for this workout is currently running.
    func isRunning(workoutId: String) async -> Bool
}

/// Owns the in-progress workout. Every change follows one path: mutate → persist → Live Activity update
/// → debounced autosave. The execution screen and the Dynamic Island buttons both go through here.
@MainActor
@Observable
public final class WorkoutSessionController {
    public enum SyncStatus: Equatable, Sendable {
        case synced
        case saving
        /// Last autosave failed; it is retried on the next change, on foreground, and on completion.
        case pending
    }

    public private(set) var session: WorkoutSessionState?
    public private(set) var syncStatus: SyncStatus = .synced
    public private(set) var isFinishing = false
    public private(set) var finishError: String?
    public var unit: WeightUnit

    private let api: RookAPI
    private let store: SessionStoring
    private let liveActivity: LiveActivityControlling
    private let clock: Clock
    private let sleep: Sleeper
    private let autosaveDelay: Duration
    private let onSessionExpired: @MainActor () async -> Void
    private var autosaveTask: Task<Void, Never>?
    private var lastSentContent: WorkoutActivityAttributes.ContentState?

    public init(
        api: RookAPI,
        store: SessionStoring,
        liveActivity: LiveActivityControlling,
        unit: WeightUnit,
        clock: Clock = .system,
        sleep: @escaping Sleeper = systemSleeper,
        autosaveDelay: Duration = .milliseconds(500),
        onSessionExpired: @escaping @MainActor () async -> Void
    ) {
        self.api = api
        self.store = store
        self.liveActivity = liveActivity
        self.unit = unit
        self.clock = clock
        self.sleep = sleep
        self.autosaveDelay = autosaveDelay
        self.onSessionExpired = onSessionExpired
    }

    public var isActive: Bool { session != nil }
    public var now: Date { clock.now() }

    // MARK: - Lifecycle

    /// On launch: resume a persisted workout (and its Live Activity) or clear stale activities.
    public func restore() async {
        guard let saved = store.load() else {
            await liveActivity.endAll(except: nil)
            return
        }
        session = saved
        await liveActivity.endAll(except: saved.workoutId)
        lastSentContent = nil
        if await liveActivity.isRunning(workoutId: saved.workoutId) {
            await pushLiveActivity(force: true)
        } else {
            await liveActivity.start(workoutId: saved.workoutId, state: content(for: saved))
            lastSentContent = content(for: saved)
        }
    }

    /// Begins a workout the server just created.
    public func begin(with workout: WorkoutInstance) async {
        let state = WorkoutSessionState(workout: workout)
        session = state
        finishError = nil
        syncStatus = .synced
        persist()
        await liveActivity.endAll(except: nil)
        let content = content(for: state)
        await liveActivity.start(workoutId: state.workoutId, state: content)
        lastSentContent = content
    }

    /// When the app returns to the foreground: refresh the Live Activity and retry a failed save.
    public func sceneDidBecomeActive() async {
        guard session != nil else { return }
        await pushLiveActivity(force: false)
        if syncStatus == .pending { scheduleAutosave(immediately: true) }
    }

    // MARK: - Actions

    public func togglePause() async {
        await mutate(changesExercises: false) { s, now in s.isPaused ? s.resume(at: now) : s.pause(at: now) }
    }

    public func goToNext() async {
        await mutate(changesExercises: false) { s, _ in s.advance() }
    }

    public func goToPrevious() async {
        await mutate(changesExercises: false) { s, _ in s.goBack() }
    }

    public func setWeight(_ weight: Double) async {
        let unit = unit
        await mutate(changesExercises: true) { s, _ in s.setWeight(weight, unit: s.currentExercise?.weightUnit ?? unit) }
    }

    /// Skips the current exercise and moves on (unless it's the last).
    public func skipCurrent() async {
        await mutate(changesExercises: true) { s, _ in
            s.skipCurrent()
            s.advance()
        }
    }

    public func toggleDuration() async {
        await mutate(changesExercises: false) { s, now in
            s.isDurationRunning ? s.pauseDuration(at: now) : s.startDuration(at: now)
        }
    }

    /// Marks the timed exercise done and moves on (unless it's the last).
    public func completeDuration() async {
        let unit = unit
        await mutate(changesExercises: true) { s, _ in
            s.completeDuration(unit: unit)
            s.advance()
        }
    }

    /// "Next" from the Live Activity: records a weight only if one is already logged, then advances.
    public func advanceFromLiveActivity() async {
        guard let session, !session.isLast else { return }
        await goToNext()
    }

    // MARK: - Finish

    /// Completes the workout on the server. On failure the session is kept so nothing is lost.
    @discardableResult
    public func complete() async -> Bool {
        guard let session, session.canComplete, !isFinishing else { return false }
        isFinishing = true
        finishError = nil
        autosaveTask?.cancel()
        defer { isFinishing = false }
        do {
            _ = try await api.updateWorkout(id: session.workoutId, .complete(session.exercises))
            await finishLocally(workoutId: session.workoutId)
            return true
        } catch APIError.rejected(400, let message) where message.localizedCaseInsensitiveContains("completed or cancelled") {
            // Already finished (e.g. on the web): nothing left to save.
            await finishLocally(workoutId: session.workoutId)
            return true
        } catch {
            if isSessionExpired(error) { await onSessionExpired(); return false }
            finishError = "Couldn't save your workout. \(userMessage(for: error)) Your progress is kept on this phone."
            return false
        }
    }

    /// Cancels the workout on the server and discards it locally.
    @discardableResult
    public func cancel() async -> Bool {
        guard let session, !isFinishing else { return false }
        isFinishing = true
        finishError = nil
        autosaveTask?.cancel()
        defer { isFinishing = false }
        do {
            _ = try await api.updateWorkout(id: session.workoutId, .cancel)
        } catch APIError.rejected(400, _) {
            // Already completed/cancelled server-side: fine to discard.
        } catch {
            if isSessionExpired(error) { await onSessionExpired(); return false }
            finishError = "Couldn't cancel on the server. \(userMessage(for: error))"
            return false
        }
        await finishLocally(workoutId: session.workoutId)
        return true
    }

    /// Discards the local session without contacting the server (e.g. "Discard anyway", or sign-out).
    public func discardLocally() async {
        guard let session else { return }
        autosaveTask?.cancel()
        await finishLocally(workoutId: session.workoutId)
    }

    // MARK: - Internals

    private func mutate(changesExercises: Bool, _ body: (inout WorkoutSessionState, Date) -> Void) async {
        guard var state = session else { return }
        body(&state, clock.now())
        guard state != session else { return }
        session = state
        persist()
        if changesExercises || syncStatus == .pending { scheduleAutosave(immediately: false) }
        await pushLiveActivity(force: false)
    }

    private func persist() {
        guard let session else { return }
        try? store.save(session)
    }

    private func content(for state: WorkoutSessionState) -> WorkoutActivityAttributes.ContentState {
        ContentStateBuilder.make(from: state, unit: unit, now: clock.now())
    }

    /// Sends Live Activity content only when it changed (timers are date-anchored, so no polling).
    private func pushLiveActivity(force: Bool) async {
        guard let session else { return }
        let content = content(for: session)
        guard force || content != lastSentContent else { return }
        lastSentContent = content
        await liveActivity.update(workoutId: session.workoutId, state: content)
    }

    private func scheduleAutosave(immediately: Bool) {
        autosaveTask?.cancel()
        let delay = autosaveDelay
        autosaveTask = Task { [weak self, sleep] in
            if !immediately {
                do { try await sleep(delay) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await self?.autosave()
        }
    }

    /// Waits for a scheduled autosave (tests).
    public func waitForAutosave() async { await autosaveTask?.value }

    private func autosave() async {
        guard let session else { return }
        syncStatus = .saving
        do {
            _ = try await api.updateWorkout(id: session.workoutId, .progress(session.exercises))
            if self.session?.workoutId == session.workoutId { syncStatus = .synced }
        } catch {
            if isSessionExpired(error) { await onSessionExpired(); return }
            syncStatus = .pending
        }
    }

    private func finishLocally(workoutId: String) async {
        session = nil
        syncStatus = .synced
        lastSentContent = nil
        try? store.clear()
        await liveActivity.end(workoutId: workoutId)
    }
}
