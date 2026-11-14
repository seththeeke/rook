import Foundation

extension RookFormat {
    /// "Today", "Yesterday", "3 days ago" (within a week), otherwise "Mar 14" (or "Mar 14, 2025" in another year).
    /// Uses calendar days, not 24-hour windows, so 11pm yesterday is "Yesterday" at 1am today.
    public static func relativeDay(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let days = CalendarMath.daysBetween(date, now, calendar: calendar)
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days) days ago"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
            return formatter.string(from: date)
        }
    }

    /// Relative day for a server day key ("2026-03-14"), interpreted as that calendar day locally.
    public static func relativeDay(
        dayKey: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let key = DayKey(dayKey),
              let date = calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day, hour: 12))
        else { return nil }
        return relativeDay(date, now: now, calendar: calendar, locale: locale)
    }

    /// "March 2026": used for the profile's "Member since".
    public static func monthYear(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMMy")
        return formatter.string(from: date)
    }
}
