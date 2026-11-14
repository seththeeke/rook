import Foundation
import RookFormatting

/// What a day in the week strip shows.
public enum DayActivity: String, Codable, Equatable, Sendable {
    case none
    /// One workout (not sauna).
    case workout
    /// One sauna session.
    case sauna
    /// More than one session that day, or a completed day whose workouts aren't loaded.
    case multiple
}

/// The dashboard figures the home-screen widgets show. The app writes it to the shared App Group
/// container after each dashboard load; the widget extension only reads it (it has no session or API).
public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var workoutsLast30Days: Int
    public var saunaSessionsLast30Days: Int
    /// Activity per local day ("YYYY-MM-DD"); days without activity are left out.
    public var days: [String: DayActivity]
    /// Today's steps as last seen by the app, and the local day they belong to.
    public var steps: Int?
    public var stepsDay: String?

    public init(
        updatedAt: Date,
        workoutsLast30Days: Int,
        saunaSessionsLast30Days: Int,
        days: [String: DayActivity],
        steps: Int? = nil,
        stepsDay: String? = nil
    ) {
        self.updatedAt = updatedAt
        self.workoutsLast30Days = workoutsLast30Days
        self.saunaSessionsLast30Days = saunaSessionsLast30Days
        self.days = days
        self.steps = steps
        self.stepsDay = stepsDay
    }

    /// The same snapshot without the fields that change constantly (time and steps). Used to decide
    /// whether the widgets need reloading.
    public var content: DashboardSnapshot {
        var copy = self
        copy.updatedAt = .distantPast
        copy.steps = nil
        copy.stepsDay = nil
        return copy
    }
}

/// Reads and writes the snapshot as JSON in the App Group container.
public struct DashboardSnapshotStore: Sendable {
    public static let appGroup = "group.com.rookfitness.app"
    public static let fileName = "dashboard-snapshot.json"

    public let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    /// The store in the shared App Group container (nil URL when the entitlement is missing).
    public static var shared: DashboardSnapshotStore {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        return DashboardSnapshotStore(url: container?.appendingPathComponent(fileName))
    }

    public func load() -> DashboardSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(DashboardSnapshot.self, from: data)
    }

    public func save(_ snapshot: DashboardSnapshot) {
        guard let url, let data = try? Self.encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// What a widget displays at a given moment, derived from the snapshot.
public struct WidgetSummary: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public var key: String
        public var letter: String
        public var isToday: Bool
        public var activity: DayActivity
    }

    /// nil when the app hasn't written a snapshot yet (signed out, or never opened).
    public var workoutsLast30Days: Int?
    public var saunaSessionsLast30Days: Int?
    /// nil when unknown for today.
    public var steps: Int?
    public var week: [Day]
    public var hasData: Bool { workoutsLast30Days != nil }

    /// - Parameters:
    ///   - liveSteps: today's count read by the widget itself, preferred over the app's last value.
    public init(snapshot: DashboardSnapshot?, now: Date, liveSteps: Int? = nil, calendar: Calendar = .current) {
        let today = DayKey(localDay: now, calendar: calendar).description
        workoutsLast30Days = snapshot?.workoutsLast30Days
        saunaSessionsLast30Days = snapshot?.saunaSessionsLast30Days
        steps = liveSteps ?? (snapshot?.stepsDay == today ? snapshot?.steps : nil)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        week = CalendarMath.mondayWeek(containing: now, calendar: calendar).enumerated().map { index, date in
            let key = DayKey(localDay: date, calendar: calendar).description
            return Day(key: key, letter: letters[index], isToday: key == today, activity: snapshot?.days[key] ?? .none)
        }
    }

    /// Placeholder shown in the widget gallery.
    public static func sample(now: Date = Date(), calendar: Calendar = .current) -> WidgetSummary {
        let week = CalendarMath.mondayWeek(containing: now, calendar: calendar).map { DayKey(localDay: $0, calendar: calendar).description }
        let pattern: [DayActivity] = [.workout, .sauna, .none, .multiple, .workout, .none, .none]
        let days = Dictionary(uniqueKeysWithValues: zip(week, pattern).filter { $0.1 != .none })
        return WidgetSummary(
            snapshot: DashboardSnapshot(updatedAt: now, workoutsLast30Days: 12, saunaSessionsLast30Days: 6, days: days),
            now: now, liveSteps: 8_432, calendar: calendar
        )
    }
}
