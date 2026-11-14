import Foundation
import Observation
import RookFormatting
import RookModels
import RookNetworking

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
        public var totalWorkouts: Int
        public var workoutsLast30Days: Int
        public var volumeLast30Days: Double
        public var minutesLast30Days: Int
    }

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
        public var hasWorkout: Bool
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

    public func load() async {
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
        return Stats(
            totalWorkouts: max(global.totalWorkouts, completedWorkouts.count),
            workoutsLast30Days: recent.count,
            volumeLast30Days: recent.reduce(0) { $0 + WorkoutPresentation.volume(for: $1) },
            minutesLast30Days: recent.reduce(0) { $0 + WorkoutPresentation.minutes(for: $1) }
        )
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
        let completed = DayKey.set(from: global.completedDates)
            .union(completedWorkouts.compactMap { $0.completedAt.map(DayKey.init(utcDayOf:)) })
        let today = DayKey(localDay: clock.now(), calendar: calendar)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return CalendarMath.mondayWeek(containing: clock.now(), calendar: calendar).enumerated().map { index, date in
            let key = DayKey(localDay: date, calendar: calendar)
            return WeekDay(date: date, key: key, letter: letters[index], isToday: key == today, hasWorkout: completed.contains(key))
        }
    }

    public var recentWorkouts: [WorkoutInstance] { Array(completedWorkouts.prefix(5)) }

    static func pounds(_ weight: Double, _ unit: WeightUnit?) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }
}

/// Month calendar of workout days, with the workouts for a selected day.
@MainActor
@Observable
public final class CalendarModel {
    public struct Day: Equatable, Identifiable, Sendable {
        public var id: String { key.description }
        public var date: Date
        public var key: DayKey
        public var dayNumber: Int
        public var hasWorkout: Bool
        public var isToday: Bool
        public var isFuture: Bool
    }

    public private(set) var month: Date
    public var selectedDay: DayKey?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private var completedKeys: Set<DayKey>
    private var pager = CompletedWorkoutPager()
    private var workouts: [WorkoutInstance]
    private let api: RookAPI
    private let clock: Clock
    private let calendar: Calendar

    public init(
        api: RookAPI,
        completedDates: [String],
        knownWorkouts: [WorkoutInstance],
        clock: Clock = .system,
        calendar: Calendar = .current
    ) {
        self.api = api
        self.clock = clock
        self.calendar = calendar
        self.workouts = knownWorkouts
        self.completedKeys = DayKey.set(from: completedDates)
            .union(knownWorkouts.compactMap { $0.completedAt.map(DayKey.init(utcDayOf:)) })
        self.month = calendar.dateInterval(of: .month, for: clock.now())?.start ?? clock.now()
    }

    public var title: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMMy")
        return formatter.string(from: month)
    }

    public var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { return false }
        return next <= clock.now()
    }

    public func showPreviousMonth() async {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: month) else { return }
        month = previous
        selectedDay = nil
        await loadWorkoutsForVisibleMonth()
    }

    public func showNextMonth() {
        guard canGoForward, let next = calendar.date(byAdding: .month, value: 1, to: month) else { return }
        month = next
        selectedDay = nil
    }

    /// Grid cells, Monday first; nil entries are blank leading cells.
    public var grid: [Day?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month) // 1 = Sunday
        let leading = (weekday + 5) % 7
        let today = DayKey(localDay: clock.now(), calendar: calendar)
        let days: [Day?] = range.compactMap { day -> Day? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: month) else { return nil }
            let key = DayKey(localDay: date, calendar: calendar)
            return Day(date: date, key: key, dayNumber: day, hasWorkout: completedKeys.contains(key), isToday: key == today, isFuture: key > today)
        }
        return Array(repeating: nil, count: leading) + days
    }

    public var workoutsOnSelectedDay: [WorkoutInstance] {
        guard let selectedDay else { return [] }
        return workouts.filter { $0.completedAt.map(DayKey.init(utcDayOf:)) == selectedDay }
    }

    /// Makes sure workouts back to the start of the visible month are loaded (for the day list).
    public func loadWorkoutsForVisibleMonth() async {
        let oldestKnown = workouts.compactMap(\.completedAt).min()
        guard oldestKnown.map({ $0 > month }) ?? true, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var working = pager
            try await working.load(api: api, coveringBack: month, maxPages: 10)
            pager = working
            let existing = Set(workouts.map(\.id))
            workouts += pager.workouts.filter { !existing.contains($0.id) }
            completedKeys.formUnion(pager.workouts.compactMap { $0.completedAt.map(DayKey.init(utcDayOf:)) })
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
