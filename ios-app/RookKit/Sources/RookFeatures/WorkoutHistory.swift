import Foundation
import Observation
import RookFormatting
import RookModels
import RookNetworking

/// Pages through `GET /workout-instances` keeping only completed workouts.
///
/// The server's `status` filter is applied after its page limit (spec §6.3), so we never send it; a page
/// can contain zero completed workouts, and the pager keeps going until it finds some or runs out.
public struct CompletedWorkoutPager: Sendable {
    public static let pageSize = 50

    public private(set) var workouts: [WorkoutInstance] = []
    public private(set) var nextToken: String?
    public private(set) var isExhausted = false
    private var seen: Set<String> = []

    public init() {}

    /// The oldest completion time loaded so far.
    public var oldestCompletedAt: Date? { workouts.last?.completedAt }

    /// Loads one more server page. Returns how many new completed workouts were added.
    @discardableResult
    public mutating func loadNextPage(api: RookAPI) async throws -> Int {
        guard !isExhausted else { return 0 }
        let page = try await api.fetchWorkouts(limit: Self.pageSize, nextToken: nextToken)
        nextToken = page.nextToken
        isExhausted = page.nextToken == nil
        let fresh = page.items.filter { $0.status == .completed && $0.completedAt != nil && !seen.contains($0.id) }
        fresh.forEach { seen.insert($0.id) }
        workouts.append(contentsOf: fresh)
        workouts.sort { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return fresh.count
    }

    /// Keeps loading until at least `minimumCount` workouts are loaded, or the oldest loaded workout is
    /// older than `cutoff`, or `maxPages` pages were fetched, or the history is exhausted.
    public mutating func load(
        api: RookAPI,
        minimumCount: Int = 0,
        coveringBack cutoff: Date? = nil,
        maxPages: Int = 6
    ) async throws {
        var pages = 0
        while !isExhausted, pages < maxPages {
            let coversCutoff = cutoff.map { cutoff in (oldestCompletedAt.map { $0 < cutoff } ?? false) } ?? true
            if workouts.count >= minimumCount, coversCutoff, pages > 0 || !workouts.isEmpty { break }
            try await loadNextPage(api: api)
            pages += 1
        }
    }
}

/// Display helpers for a workout.
public enum WorkoutPresentation {
    /// "Bench, Squat, Row +2": first words of the first three exercise names (as the web app shows).
    public static func title(for workout: WorkoutInstance) -> String {
        let names = workout.orderedExercises.map(\.exerciseName)
        guard !names.isEmpty else { return workout.gymName ?? "Workout" }
        let shown = names.prefix(3).map { $0.split(separator: " ").first.map(String.init) ?? $0 }
        let extra = names.count - shown.count
        return shown.joined(separator: ", ") + (extra > 0 ? " +\(extra)" : "")
    }

    /// Total volume as calculated and stored by the server at completion (0 if absent).
    /// The app never computes volume itself.
    public static func volume(for workout: WorkoutInstance) -> Double {
        workout.totalVolume ?? 0
    }

    /// "3 × 8 @ 135 lbs", "60 s", "Skipped".
    public static func detail(for exercise: WorkoutExercise, fallbackUnit: WeightUnit) -> String {
        if exercise.skipped { return "Skipped" }
        if exercise.modality.isTimed {
            return "\(exercise.durationSeconds ?? WorkoutExercise.defaultDurationSeconds) s"
        }
        let scheme = "\(exercise.sets ?? WorkoutExercise.defaultSets) × \(exercise.reps ?? WorkoutExercise.defaultReps)"
        guard let weight = exercise.weight else { return scheme }
        if weight == 0 { return "\(scheme) · Bodyweight" }
        return "\(scheme) @ \(RookFormat.weight(weight, unit: exercise.weightUnit ?? fallbackUnit))"
    }

    /// Minutes the workout took (server figure, else derived from timestamps).
    public static func minutes(for workout: WorkoutInstance) -> Int {
        if let minutes = workout.durationMinutes { return minutes }
        guard let completed = workout.completedAt else { return 0 }
        return max(0, Int(completed.timeIntervalSince(workout.startedAt) / 60))
    }
}

/// Paginated list of completed workouts (dashboard "See all", and the builder's "past workout" picker).
@MainActor
@Observable
public final class HistoryModel {
    public private(set) var workouts: [WorkoutInstance] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var reachedEnd = false
    public private(set) var errorMessage: String?

    private var pager = CompletedWorkoutPager()
    private let api: RookAPI
    private let onSessionExpired: @MainActor () async -> Void

    public init(api: RookAPI, onSessionExpired: @escaping @MainActor () async -> Void) {
        self.api = api
        self.onSessionExpired = onSessionExpired
    }

    public func loadFirstPage() async {
        guard !hasLoaded else { return }
        await loadMore(minimum: 20)
    }

    /// Call as rows appear; loads more when the last row becomes visible.
    public func loadMoreIfNeeded(currentId: String) async {
        guard currentId == workouts.last?.id else { return }
        await loadMore(minimum: workouts.count + 20)
    }

    public func retry() async {
        await loadMore(minimum: max(20, workouts.count + 1))
    }

    private func loadMore(minimum: Int) async {
        guard !isLoading, !pager.isExhausted else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var working = pager
            try await working.load(api: api, minimumCount: minimum, maxPages: 4)
            pager = working
            workouts = pager.workouts
            reachedEnd = pager.isExhausted
            hasLoaded = true
        } catch {
            if isSessionExpired(error) { await onSessionExpired(); return }
            errorMessage = userMessage(for: error)
        }
    }
}
