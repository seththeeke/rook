import Foundation

/// A calendar day as the backend stores it: "YYYY-MM-DD".
///
/// The metrics processor derives day keys with `new Date().toISOString().split('T')[0]`, i.e. in **UTC**
/// (`init(utcDayOf:)` reproduces that). Those keys put late-evening sessions on the following day, so
/// anything the user *sees* keys timestamps by their local calendar day instead
/// (`init(localDay:calendar:)`), and `GlobalMetrics.completedDates` isn't used to place sessions on days.
public struct DayKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "YYYY-MM-DD" (extra time components are ignored, e.g. "2026-03-14T…").
    public init?(_ string: String) {
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The UTC calendar day containing `date` (matches the server's `toISOString()` split).
    public init(utcDayOf date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// The calendar day `date` falls on in `calendar`'s time zone (what the user sees on screen).
    public init(localDay date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Converts server day-key strings into a set for fast membership checks; invalid strings are dropped.
    public static func set(from strings: [String]) -> Set<DayKey> {
        Set(strings.compactMap(DayKey.init))
    }
}

/// Calendar helpers for week and month views.
public enum CalendarMath {
    /// The seven local days (Monday first) of the week containing `date`.
    public static func mondayWeek(containing date: Date, calendar: Calendar = .current) -> [Date] {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let startOfDay = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: startOfDay) // 1 = Sunday … 7 = Saturday
        let offsetFromMonday = (weekday + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -offsetFromMonday, to: startOfDay) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    /// Whole calendar days from `earlier` to `later` in `calendar` (0 = same day, 1 = yesterday, …).
    public static func daysBetween(_ earlier: Date, _ later: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: earlier)
        let b = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
