import Foundation
import RookModels

/// The in-progress workout, as a pure value. Every time-dependent answer takes `at now: Date`, so the
/// state never drifts (it is derived from wall-clock anchors) and tests are deterministic.
///
/// Ported from `packages/web/src/stores/workoutSessionStore.ts`:
/// - elapsed = now − startedAt − (completed pauses + the in-progress pause)
/// - a duration exercise has a "segment" with its own run/pause anchors, scoped to one exercise index
public struct WorkoutSessionState: Codable, Equatable, Sendable {
    public struct DurationSegment: Codable, Equatable, Sendable {
        public var exerciseIndex: Int
        public var isRunning: Bool
        /// Set while running: when the current run started.
        public var runningSince: Date?
        /// Seconds accumulated by previous runs of this segment.
        public var accumulatedSeconds: Int
    }

    public var workoutId: String
    /// Shown in the Live Activity (gym name, notes, or nil for the generic label).
    public var displayName: String?
    public var exercises: [WorkoutExercise]
    public private(set) var currentIndex: Int
    public private(set) var startedAt: Date
    public private(set) var isPaused: Bool
    /// Total paused time from completed pauses.
    public private(set) var totalPaused: TimeInterval
    public private(set) var pauseStartedAt: Date?
    public private(set) var durationSegment: DurationSegment?

    public init(
        workoutId: String,
        displayName: String?,
        exercises: [WorkoutExercise],
        startedAt: Date
    ) {
        self.workoutId = workoutId
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.exercises = exercises.sorted { $0.orderIndex < $1.orderIndex }
        self.currentIndex = 0
        self.startedAt = startedAt
        self.isPaused = false
        self.totalPaused = 0
        self.pauseStartedAt = nil
        self.durationSegment = nil
    }

    /// Starts a session for a workout the server just created (or that is resumed from the server).
    /// `startedAt` comes from the server so the timer matches the recorded workout duration.
    public init(workout: WorkoutInstance, displayName: String? = nil) {
        self.init(
            workoutId: workout.workoutInstanceId,
            displayName: displayName ?? workout.notes ?? workout.gymName,
            exercises: workout.exercises,
            startedAt: workout.startedAt
        )
    }

    // MARK: - Derived

    public var currentExercise: WorkoutExercise? {
        exercises.indices.contains(currentIndex) ? exercises[currentIndex] : nil
    }
    public var isFirst: Bool { currentIndex == 0 }
    public var isLast: Bool { currentIndex >= exercises.count - 1 }
    public var skippedCount: Int { exercises.filter(\.skipped).count }

    /// Indices of exercises that would make the server reject completion (spec §6.5).
    public var completionBlockers: [Int] {
        exercises.indices.filter { !exercises[$0].isReadyForCompletion }
    }
    public var canComplete: Bool { !exercises.isEmpty && completionBlockers.isEmpty }

    /// Paused time up to `now`, including a pause in progress.
    public func pausedInterval(at now: Date) -> TimeInterval {
        var paused = totalPaused
        if isPaused, let pauseStartedAt { paused += max(0, now.timeIntervalSince(pauseStartedAt)) }
        return paused
    }

    /// Active (unpaused) workout seconds at `now`. Mirrors `computeSessionElapsedSeconds`.
    public func elapsedSeconds(at now: Date) -> Int {
        let active = now.timeIntervalSince(startedAt) - pausedInterval(at: now)
        return max(0, Int(active.rounded(.down)))
    }

    /// The instant a running elapsed-timer would display as 00:00 (`Text(date, style: .timer)` anchor).
    public var timerReferenceDate: Date { startedAt.addingTimeInterval(totalPaused) }

    /// Target seconds for the current duration exercise.
    public var currentDurationTarget: Int {
        currentExercise?.durationSeconds ?? WorkoutExercise.defaultDurationSeconds
    }

    public var isDurationRunning: Bool {
        durationSegment?.exerciseIndex == currentIndex && durationSegment?.isRunning == true
    }

    /// Seconds elapsed in the current exercise's duration segment, clamped to its target.
    /// Mirrors `computeDurationElapsedSeconds`.
    public func durationElapsedSeconds(at now: Date) -> Int {
        guard let segment = durationSegment, segment.exerciseIndex == currentIndex else { return 0 }
        var elapsed = segment.accumulatedSeconds
        if segment.isRunning, let since = segment.runningSince {
            elapsed += Int(max(0, now.timeIntervalSince(since)).rounded(.down))
        }
        return min(max(0, elapsed), currentDurationTarget)
    }

    public func durationRemainingSeconds(at now: Date) -> Int {
        max(0, currentDurationTarget - durationElapsedSeconds(at: now))
    }

    /// When the running duration segment will hit zero (nil when not running).
    public func durationEndDate(at now: Date) -> Date? {
        guard isDurationRunning else { return nil }
        return now.addingTimeInterval(TimeInterval(durationRemainingSeconds(at: now)))
    }

    // MARK: - Session timer

    public mutating func pause(at now: Date) {
        guard !isPaused else { return }
        pauseDuration(at: now)
        isPaused = true
        pauseStartedAt = now
    }

    public mutating func resume(at now: Date) {
        guard isPaused else { return }
        if let pauseStartedAt { totalPaused += max(0, now.timeIntervalSince(pauseStartedAt)) }
        isPaused = false
        pauseStartedAt = nil
    }

    // MARK: - Navigation

    /// Moves to `index` (clamped). Leaving an exercise discards its duration segment, as on the web.
    public mutating func goTo(_ index: Int) {
        guard !exercises.isEmpty else { return }
        let clamped = min(max(0, index), exercises.count - 1)
        guard clamped != currentIndex else { return }
        currentIndex = clamped
        durationSegment = nil
    }

    /// Advances to the next exercise. Returns false when already on the last one.
    @discardableResult
    public mutating func advance() -> Bool {
        guard !isLast else { return false }
        goTo(currentIndex + 1)
        return true
    }

    @discardableResult
    public mutating func goBack() -> Bool {
        guard !isFirst else { return false }
        goTo(currentIndex - 1)
        return true
    }

    // MARK: - Logging

    /// Records the weight for the current exercise (and un-skips it).
    public mutating func setWeight(_ weight: Double, unit: WeightUnit) {
        guard exercises.indices.contains(currentIndex) else { return }
        exercises[currentIndex].weight = weight
        exercises[currentIndex].weightUnit = unit
        exercises[currentIndex].skipped = false
    }

    public mutating func skipCurrent() {
        guard exercises.indices.contains(currentIndex) else { return }
        exercises[currentIndex].skipped = true
        if durationSegment?.exerciseIndex == currentIndex { durationSegment = nil }
    }

    // MARK: - Duration exercises

    /// Starts (or resumes) the current exercise's countdown. Starting a timer while the workout is
    /// paused also resumes the workout, since the user is clearly exercising.
    public mutating func startDuration(at now: Date) {
        guard currentExercise != nil else { return }
        resume(at: now)
        if var segment = durationSegment, segment.exerciseIndex == currentIndex {
            guard !segment.isRunning else { return }
            segment.isRunning = true
            segment.runningSince = now
            durationSegment = segment
        } else {
            durationSegment = DurationSegment(exerciseIndex: currentIndex, isRunning: true, runningSince: now, accumulatedSeconds: 0)
        }
    }

    public mutating func pauseDuration(at now: Date) {
        guard var segment = durationSegment, segment.exerciseIndex == currentIndex, segment.isRunning else { return }
        if let since = segment.runningSince {
            segment.accumulatedSeconds += Int(max(0, now.timeIntervalSince(since)).rounded(.down))
        }
        segment.isRunning = false
        segment.runningSince = nil
        durationSegment = segment
    }

    /// Marks the current duration exercise done. The server requires a weight on every non-skipped
    /// exercise's record, so timed work is logged with weight 0 (as the web app does).
    public mutating func completeDuration(unit: WeightUnit) {
        guard exercises.indices.contains(currentIndex) else { return }
        exercises[currentIndex].weight = 0
        exercises[currentIndex].weightUnit = unit
        exercises[currentIndex].skipped = false
        if exercises[currentIndex].durationSeconds == nil {
            exercises[currentIndex].durationSeconds = currentDurationTarget
        }
        durationSegment = nil
    }
}
