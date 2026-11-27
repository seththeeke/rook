import Foundation
import Observation
import RookFormatting
import RookModels
import RookNetworking

// Exercise trends (specs/exercise-trends.md): per-exercise progression charts, the dashboard's
// Recent Exercises card and the Personal Records sparklines.

/// The chart's time filters. All four are applied on the client to one all-time fetch, so switching is
/// instant and the chart can animate between them.
public enum TrendRange: String, CaseIterable, Identifiable, Sendable {
    case days30, days90, yearToDate, allTime

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .days30: "30 Days"
        case .days90: "90 Days"
        case .yearToDate: "YTD"
        case .allTime: "All Time"
        }
    }

    /// Phrase for empty states and accessibility ("in the past 30 days").
    public var phrase: String {
        switch self {
        case .days30: "in the past 30 days"
        case .days90: "in the past 90 days"
        case .yearToDate: "this year"
        case .allTime: "yet"
        }
    }

    /// First instant included, or nil for all time.
    public func start(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .days30: calendar.date(byAdding: .day, value: -30, to: now)
        case .days90: calendar.date(byAdding: .day, value: -90, to: now)
        case .yearToDate: calendar.date(from: calendar.dateComponents([.year], from: now))
        case .allTime: nil
        }
    }
}

/// What a trend plots for an exercise: its working weight, or reps for bodyweight exercises, or minutes
/// for timed ones.
public enum TrendMetric: Equatable, Sendable {
    case weight(WeightUnit)
    case reps
    case minutes

    /// Weight whenever any session logged one; otherwise minutes for timed exercises, else reps.
    public static func best(for sessions: [ExerciseSession], unit: WeightUnit) -> TrendMetric {
        if sessions.contains(where: { $0.weight > 0 }) { return .weight(unit) }
        let timed = sessions.contains { $0.modality?.isTimed == true || ($0.reps == nil && ($0.durationSeconds ?? 0) > 0) }
        return timed ? .minutes : .reps
    }

    /// The session's value in this metric, or nil when it doesn't have one.
    public func value(of session: ExerciseSession) -> Double? {
        switch self {
        case .weight(let unit):
            return TrendMath.convert(session.weight, from: session.weightUnit ?? unit, to: unit)
        case .reps:
            return session.reps.map(Double.init)
        case .minutes:
            return session.durationSeconds.map { Double($0) / 60 }
        }
    }

    /// "135 lbs", "12 reps", "20 min".
    public func format(_ value: Double) -> String {
        switch self {
        case .weight(let unit): RookFormat.weight(value, unit: unit)
        case .reps: "\(RookFormat.weight(value)) reps"
        case .minutes: "\(RookFormat.weight((value * 10).rounded() / 10)) min"
        }
    }

    /// Signed change: "+20 lbs", "−1.5 lbs", "+2 reps".
    public func formatDelta(_ delta: Double) -> String {
        let sign = delta > 0 ? "+" : delta < 0 ? "−" : "±"
        return sign + format(abs(delta))
    }
}

public struct TrendPoint: Equatable, Identifiable, Sendable {
    public var date: Date
    public var value: Double
    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Change from the first to the last point in view.
public struct TrendChange: Equatable, Sendable {
    public var first: Double
    public var last: Double
    public var delta: Double { last - first }
    /// nil when the starting value is zero (no meaningful percentage).
    public var percent: Double? { first == 0 ? nil : delta / first * 100 }
    public var direction: Direction { delta > 0 ? .up : delta < 0 ? .down : .flat }

    public enum Direction: Sendable { case up, down, flat }

    /// "+20 lbs · +17%".
    public func label(metric: TrendMetric) -> String {
        var text = metric.formatDelta(delta)
        if let percent {
            let rounded = abs(percent) < 10 ? (percent * 10).rounded() / 10 : percent.rounded()
            text += " · \(rounded > 0 ? "+" : rounded < 0 ? "−" : "±")\(RookFormat.weight(abs(rounded)))%"
        }
        return text
    }
}

public enum TrendMath {
    static let poundsPerKilogram = 2.20462

    public static func convert(_ value: Double, from: WeightUnit, to: WeightUnit) -> Double {
        guard from != to else { return value }
        let converted = to == .kg ? value / poundsPerKilogram : value * poundsPerKilogram
        return (converted * 10).rounded() / 10
    }

    public static func points(_ sessions: [ExerciseSession], metric: TrendMetric) -> [TrendPoint] {
        sessions
            .sorted { $0.completedAt < $1.completedAt }
            .compactMap { session in metric.value(of: session).map { TrendPoint(date: session.completedAt, value: $0) } }
    }

    public static func visible(_ points: [TrendPoint], range: TrendRange, now: Date, calendar: Calendar) -> [TrendPoint] {
        guard let start = range.start(now: now, calendar: calendar) else { return points }
        return points.filter { $0.date >= start }
    }

    /// Y axis fitted to the values in view, so small lifts show their progress as clearly as big ones.
    /// Never fixed at zero; a flat series gets a small span (±5%, at least ±1) so it sits mid-chart.
    public static func yDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = high > low ? (high - low) * 0.2 : max(abs(high) * 0.05, 1)
        let lower = low >= 0 ? max(0, low - pad) : low - pad
        return lower...(high + pad)
    }

    /// X axis: the filter's start to now, or first session to now for all time. The end is padded by 4%
    /// of the span (at least 12 hours) so the newest point isn't cut off at the plot edge.
    public static func xDomain(_ points: [TrendPoint], range: TrendRange, now: Date, calendar: Calendar) -> ClosedRange<Date> {
        let start = range.start(now: now, calendar: calendar) ?? points.first?.date ?? now
        let end = max(now, points.last?.date ?? now)
        if end.timeIntervalSince(start) < 86_400 {
            return start.addingTimeInterval(-86_400)...end.addingTimeInterval(86_400)
        }
        return start...end.addingTimeInterval(max(end.timeIntervalSince(start) * 0.04, 43_200))
    }

    public static func change(_ points: [TrendPoint]) -> TrendChange? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        return TrendChange(first: first.value, last: last.value)
    }
}

// MARK: - Cache

/// Session histories fetched this run, by exercise id. The dashboard clears it on every load (so a
/// just-finished workout shows up); otherwise reopening an exercise doesn't refetch.
@MainActor
public final class ExerciseSessionCache {
    private var storage: [String: [ExerciseSession]] = [:]

    public init() {}

    public subscript(exerciseId: String) -> [ExerciseSession]? {
        get { storage[exerciseId] }
        set { storage[exerciseId] = newValue }
    }

    public func removeAll() { storage.removeAll() }
}

// MARK: - Model

/// One exercise's trend screen.
@MainActor
@Observable
public final class ExerciseTrendModel {
    public enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public let exerciseId: String
    public let exerciseName: String
    public private(set) var state: LoadState = .loading
    public private(set) var sessions: [ExerciseSession] = []
    public var range: TrendRange = .days90

    /// The profile's unit; weights are shown in it.
    public let unit: WeightUnit
    private let api: RookAPI
    private let cache: ExerciseSessionCache
    private let clock: Clock
    private let calendar: Calendar
    private let onSessionExpired: @MainActor () async -> Void

    public init(
        exerciseId: String,
        exerciseName: String,
        api: RookAPI,
        unit: WeightUnit,
        cache: ExerciseSessionCache,
        clock: Clock = .system,
        calendar: Calendar = .current,
        onSessionExpired: @escaping @MainActor () async -> Void
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.api = api
        self.unit = unit
        self.cache = cache
        self.clock = clock
        self.calendar = calendar
        self.onSessionExpired = onSessionExpired
        if let cached = cache[exerciseId] {
            sessions = cached
            state = .loaded
        }
    }

    public func load() async {
        if cache[exerciseId] != nil, state == .loaded { return }
        state = .loading
        do {
            let fetched = try await api.fetchExerciseSessions(exerciseId: exerciseId)
            sessions = fetched.sorted { $0.completedAt < $1.completedAt }
            cache[exerciseId] = sessions
            state = .loaded
        } catch {
            if isSessionExpired(error) { await onSessionExpired(); return }
            state = .failed(userMessage(for: error))
        }
    }

    public func retry() async {
        cache[exerciseId] = nil
        await load()
    }

    // MARK: Derived

    public var now: Date { clock.now() }
    public var metric: TrendMetric { TrendMetric.best(for: sessions, unit: unit) }
    /// Every point, all time. The chart plots all of them and animates its domains, so filters zoom.
    public var allPoints: [TrendPoint] { TrendMath.points(sessions, metric: metric) }
    public var visiblePoints: [TrendPoint] { TrendMath.visible(allPoints, range: range, now: now, calendar: calendar) }
    public var yDomain: ClosedRange<Double> { TrendMath.yDomain(visiblePoints.map(\.value)) }
    public var xDomain: ClosedRange<Date> { TrendMath.xDomain(visiblePoints, range: range, now: now, calendar: calendar) }
    public var change: TrendChange? { TrendMath.change(visiblePoints) }
    public var latest: TrendPoint? { allPoints.last }
    public var best: Double? { visiblePoints.map(\.value).max() }

    /// Sessions in the selected range, newest first (the list under the chart).
    public var visibleSessions: [ExerciseSession] {
        let start = range.start(now: now, calendar: calendar) ?? .distantPast
        return sessions.filter { $0.completedAt >= start }.reversed()
    }
}

// MARK: - Dashboard

extension DashboardModel {
    /// A row in the Recent Exercises card.
    public struct RecentExercise: Equatable, Identifiable, Sendable {
        public var id: String
        public var exerciseName: String
        /// Time of the latest session (or noon on its day for rows without an exact time).
        public var lastPerformed: Date?
        public var metric: TrendMetric
        public var latest: Double?
        /// Change since the previous session.
        public var delta: Double?
    }

    /// The 10 exercises performed most recently (sauna excluded), newest first.
    public var recentExercises: [RecentExercise] {
        exerciseMetrics
            .filter { $0.exerciseId != Sauna.exerciseId && $0.exerciseName.caseInsensitiveCompare(Sauna.exerciseName) != .orderedSame }
            .map { summary -> RecentExercise in
                let sessions = summary.recentSessions.map(ExerciseSession.init)
                // Rows written before per-session history have no sessions yet: use their weight if any.
                let metric = sessions.isEmpty && summary.maxWeight > 0 ? .weight(unit) : TrendMetric.best(for: sessions, unit: unit)
                let points = TrendMath.points(sessions, metric: metric)
                var latest = points.last?.value
                if latest == nil, case .weight = metric, let last = summary.lastUsedWeight {
                    latest = TrendMath.convert(last, from: summary.lastUsedWeightUnit ?? unit, to: unit)
                }
                let delta = points.count >= 2 ? points[points.count - 1].value - points[points.count - 2].value : nil
                return RecentExercise(
                    id: summary.exerciseId, exerciseName: summary.exerciseName,
                    lastPerformed: lastPerformed(summary), metric: metric, latest: latest, delta: delta
                )
            }
            .sorted {
                let l = $0.lastPerformed ?? .distantPast, r = $1.lastPerformed ?? .distantPast
                return l != r ? l > r : $0.exerciseName < $1.exerciseName
            }
            .prefix(10)
            .map { $0 }
    }

    private func lastPerformed(_ summary: ExerciseMetricsSummary) -> Date? {
        if let at = summary.lastPerformedAt { return at }
        guard let day = summary.lastPerformedDate, let key = DayKey(day) else { return nil }
        return calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day, hour: 12))
    }

    /// Sparkline values for a summary's recent sessions, in `unit` (reps/minutes for unweighted lifts).
    static func sparkline(_ summary: ExerciseMetricsSummary, unit: WeightUnit) -> [Double] {
        let sessions = summary.recentSessions.map(ExerciseSession.init)
        return TrendMath.points(sessions, metric: TrendMetric.best(for: sessions, unit: unit)).map(\.value)
    }
}
