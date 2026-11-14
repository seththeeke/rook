import Foundation
import Observation
import RookFormatting
import RookModels
import RookNetworking
import RookWidgetData

/// The dashboard's data and derived figures.
///
/// Fixes relative to the web dashboard (spec §6.6–6.8): "last 30 days" figures are computed from
/// workouts actually completed in the last 30 days; units come from the profile/exercise; the week strip
/// compares by the server's UTC day keys.
@MainActor
@Observable
public final class DashboardModel {
    public enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public struct Stats: Equatable, Sendable {
        /// Completed workouts in the last 30 days, not counting sauna sessions.
        public var workoutsLast30Days: Int
        /// Completed sauna-only workouts in the last 30 days.
        public var saunaSessionsLast30Days: Int
    }

    /// What a day in the week strip shows (shared with the home-screen widgets).
    public typealias DayActivity = RookWidgetData.DayActivity

    public struct PersonalRecord: Equatable, Identifiable, Sendable {
        public var id: String
        public var exerciseName: String
        public var weight: Double
        public var unit: WeightUnit
        public var sessions: Int
    }

    public struct WeekDay: Equatable, Identifiable, Sendable {
        public var id: String { key.description }
        public var date: Date
        public var key: DayKey
        public var letter: String
        public var isToday: Bool
        public var activity: DayActivity
        public var hasWorkout: Bool { activity != .none }
    }

    public private(set) var state: LoadState = .loading
    public private(set) var isRefreshing = false
    /// Non-blocking error when a refresh fails but earlier data is still shown.
    public private(set) var refreshError: String?
    public private(set) var global: GlobalMetrics = .empty
    public private(set) var exerciseMetrics: [ExerciseMetricsSummary] = []
    public private(set) var completedWorkouts: [WorkoutInstance] = []

    public var unit: WeightUnit

    private let api: RookAPI
    private let clock: Clock
    private let calendar: Calendar
    private let onSessionExpired: @MainActor () async -> Void

    public init(
        api: RookAPI,
        unit: WeightUnit,
        clock: Clock = .system,
        calendar: Calendar = .current,
        onSessionExpired: @escaping @MainActor () async -> Void
    ) {
        self.api = api
        self.unit = unit
        self.clock = clock
        self.calendar = calendar
        self.onSessionExpired = onSessionExpired
    }

    // MARK: - Loading

    /// The load currently running, shared by overlapping callers (pull-to-refresh, foregrounding, first appear).
    private var inFlight: Task<Void, Never>?

    /// Loads (or refreshes) the dashboard.
    ///
    /// The fetch runs in its own task, so cancelling the caller doesn't abort it: SwiftUI's `.refreshable`
    /// cancels its task when the view updates mid-refresh, which used to surface as an error on every pull.
    /// Overlapping calls join the load already in flight instead of starting another.
    public func load() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await performLoad() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performLoad() async {
        if state != .loaded { state = .loading } else { isRefreshing = true }
        refreshError = nil
        defer { isRefreshing = false }
        do {
            let cutoff = thirtyDaysAgo
            async let metrics = api.fetchGlobalMetrics()
            async let perExercise = api.fetchExerciseMetrics()
            async let history = Self.loadRecentHistory(api: api, cutoff: cutoff)
            let (g, e, h) = try await (metrics, perExercise, history)
            global = g
            exerciseMetrics = e
            completedWorkouts = h
            state = .loaded
        } catch is CancellationError {
            // Not a failure: keep whatever is shown, without an error message.
            if state != .loaded { state = .failed(userMessage(for: APIError.network(.cancelled))) }
        } catch {
            if isSessionExpired(error) { await onSessionExpired(); return }
            if state == .loaded {
                refreshError = userMessage(for: error)
            } else {
                state = .failed(userMessage(for: error))
            }
        }
    }

    private nonisolated static func loadRecentHistory(api: RookAPI, cutoff: Date) async throws -> [WorkoutInstance] {
        var pager = CompletedWorkoutPager()
        try await pager.load(api: api, minimumCount: 5, coveringBack: cutoff, maxPages: 6)
        return pager.workouts
    }

    // MARK: - Derived

    var thirtyDaysAgo: Date { clock.now().addingTimeInterval(-30 * 86_400) }

    public var hasAnyWorkouts: Bool { global.totalWorkouts > 0 || !completedWorkouts.isEmpty }

    public var stats: Stats {
        let cutoff = thirtyDaysAgo
        let recent = completedWorkouts.filter { ($0.completedAt ?? .distantPast) >= cutoff }
        let saunas = recent.filter(Sauna.isSaunaWorkout).count
        return Stats(workoutsLast30Days: recent.count - saunas, saunaSessionsLast30Days: saunas)
    }

    /// Top five lifts by max weight. Mixed units are compared fairly by converting to pounds.
    public var personalRecords: [PersonalRecord] {
        exerciseMetrics
            .filter { $0.maxWeight > 0 }
            .sorted { Self.pounds($0.maxWeight, $0.maxWeightUnit) > Self.pounds($1.maxWeight, $1.maxWeightUnit) }
            .prefix(5)
            .map {
                PersonalRecord(
                    id: $0.exerciseId, exerciseName: $0.exerciseName, weight: $0.maxWeight,
                    unit: $0.maxWeightUnit ?? unit, sessions: $0.totalSessions
                )
            }
    }

    public var currentWeek: [WeekDay] {
        var sessions: [DayKey: [Bool]] = [:] // day → isSauna for each loaded workout
        for workout in completedWorkouts {
            guard let completedAt = workout.completedAt else { continue }
            sessions[DayKey(utcDayOf: completedAt), default: []].append(Sauna.isSaunaWorkout(workout))
        }
        let completedDays = DayKey.set(from: global.completedDates)
        let today = DayKey(localDay: clock.now(), calendar: calendar)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return CalendarMath.mondayWeek(containing: clock.now(), calendar: calendar).enumerated().map { index, date in
            let key = DayKey(localDay: date, calendar: calendar)
            return WeekDay(
                date: date, key: key, letter: letters[index], isToday: key == today,
                activity: Self.activity(sessions[key] ?? [], completedOnServer: completedDays.contains(key))
            )
        }
    }

    public var recentWorkouts: [WorkoutInstance] { Array(completedWorkouts.prefix(5)) }

    /// The figures the home-screen widgets show; nil until the dashboard has loaded.
    public func widgetSnapshot(steps: Int?) -> DashboardSnapshot? {
        guard state == .loaded else { return nil }
        let stats = stats
        let now = clock.now()
        var days: [String: DayActivity] = [:]
        for day in currentWeek where day.activity != .none {
            days[day.key.description] = day.activity
        }
        return DashboardSnapshot(
            updatedAt: now,
            workoutsLast30Days: stats.workoutsLast30Days,
            saunaSessionsLast30Days: stats.saunaSessionsLast30Days,
            days: days,
            steps: steps,
            stepsDay: steps == nil ? nil : DayKey(localDay: now, calendar: calendar).description
        )
    }

    static func activity(_ sessions: [Bool], completedOnServer: Bool) -> DayActivity {
        switch sessions.count {
        case 0: completedOnServer ? .multiple : .none
        case 1: sessions[0] ? .sauna : .workout
        default: .multiple
        }
    }

    static func pounds(_ weight: Double, _ unit: WeightUnit?) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }
}
