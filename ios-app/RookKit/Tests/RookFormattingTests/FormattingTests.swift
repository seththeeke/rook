import Foundation
import Testing
import RookModels
@testable import RookFormatting

/// Fixed calendar/locale/time zone so results never depend on the machine running the tests.
let newYork: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    return cal
}()
let enUS = Locale(identifier: "en_US")

func date(_ iso: String) -> Date { ISO8601.parse(iso)! }

@Suite("Number formatting")
struct NumberFormattingTests {
    @Test(arguments: [
        (0.0, "0"), (950, "950"), (999.6, "1000"), (1_000, "1K"), (12_450, "12.5K"),
        (999_949, "999.9K"), (1_000_000, "1M"), (3_400_000, "3.4M"), (-5, "0"),
    ])
    func compactVolume(value: Double, expected: String) {
        #expect(RookFormat.compactVolume(value) == expected)
    }

    @Test func weights() {
        #expect(RookFormat.weight(225) == "225")
        #expect(RookFormat.weight(102.5) == "102.5")
        #expect(RookFormat.weight(102.25) == "102.25")
        #expect(RookFormat.weight(225, unit: .lbs) == "225 lbs")
        #expect(RookFormat.weight(100, unit: .kg) == "100 kg")
    }

    @Test(arguments: [(0, "00:00"), (75, "01:15"), (3_599, "59:59"), (3_725, "1:02:05"), (-3, "00:00")])
    func clock(seconds: Int, expected: String) {
        #expect(RookFormat.clock(seconds: seconds) == expected)
    }

    @Test(arguments: [
        ("135", 135.0), ("102.5", 102.5), ("102,5", 102.5), (" 45 ", 45.0), ("0", 0.0),
    ])
    func parsesValidWeights(text: String, expected: Double) {
        #expect(RookFormat.parseWeight(text) == expected)
    }

    @Test(arguments: ["", "abc", "-5", "1.2.3", "5000", "nan", "inf"])
    func rejectsInvalidWeights(text: String) {
        #expect(RookFormat.parseWeight(text) == nil)
    }
}

@Suite("Dates and day keys")
struct DateFormattingTests {
    private let now = date("2026-03-14T16:00:00Z") // Sat Mar 14, 12:00 in New York

    @Test func relativeDayUsesCalendarDays() {
        #expect(RookFormat.relativeDay(date("2026-03-14T13:00:00Z"), now: now, calendar: newYork, locale: enUS) == "Today")
        // 11pm New York yesterday → still "Yesterday" even though < 24h ago.
        #expect(RookFormat.relativeDay(date("2026-03-14T03:00:00Z"), now: now, calendar: newYork, locale: enUS) == "Yesterday")
        #expect(RookFormat.relativeDay(date("2026-03-11T16:00:00Z"), now: now, calendar: newYork, locale: enUS) == "3 days ago")
        #expect(RookFormat.relativeDay(date("2026-03-01T16:00:00Z"), now: now, calendar: newYork, locale: enUS) == "Mar 1")
        #expect(RookFormat.relativeDay(date("2025-12-25T16:00:00Z"), now: now, calendar: newYork, locale: enUS) == "Dec 25, 2025")
        // Future timestamps (clock skew) never read as "-1 days ago".
        #expect(RookFormat.relativeDay(date("2026-03-15T16:00:00Z"), now: now, calendar: newYork, locale: enUS) == "Today")
    }

    @Test func relativeDayFromDayKey() {
        #expect(RookFormat.relativeDay(dayKey: "2026-03-13", now: now, calendar: newYork, locale: enUS) == "Yesterday")
        #expect(RookFormat.relativeDay(dayKey: "garbage", now: now, calendar: newYork, locale: enUS) == nil)
    }

    @Test func monthYear() {
        #expect(RookFormat.monthYear(date("2026-03-01T15:00:00Z"), calendar: newYork, locale: enUS) == "March 2026")
    }

    @Test func dayKeyParsingAndFormatting() {
        #expect(DayKey("2026-03-04")?.description == "2026-03-04")
        #expect(DayKey("2026-03-04T10:00:00Z") == DayKey(year: 2026, month: 3, day: 4))
        #expect(DayKey("2026-13-01") == nil)
        #expect(DayKey("nope") == nil)
        #expect(DayKey(year: 2026, month: 1, day: 31) < DayKey(year: 2026, month: 2, day: 1))
        #expect(DayKey.set(from: ["2026-03-01", "bad", "2026-03-01"]).count == 1)
    }

    @Test func utcDayKeyMatchesServerForLateEveningWorkout() {
        // 9pm Friday in New York is already Saturday in UTC: the server records Saturday.
        let lateFriday = date("2026-03-14T01:00:00Z")
        #expect(DayKey(utcDayOf: lateFriday).description == "2026-03-14")
        #expect(DayKey(localDay: lateFriday, calendar: newYork).description == "2026-03-13")
    }

    @Test func mondayWeekForEachWeekday() {
        // Week of Mon Mar 9 – Sun Mar 15, 2026.
        for day in 9...15 {
            let d = newYork.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 8))!
            let week = CalendarMath.mondayWeek(containing: d, calendar: newYork)
            #expect(week.count == 7)
            #expect(DayKey(localDay: week.first!, calendar: newYork).description == "2026-03-09")
            #expect(DayKey(localDay: week.last!, calendar: newYork).description == "2026-03-15")
        }
    }

    @Test func mondayWeekAcrossYearBoundary() {
        let newYearsDay = newYork.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))! // Thursday
        let week = CalendarMath.mondayWeek(containing: newYearsDay, calendar: newYork)
        #expect(DayKey(localDay: week.first!, calendar: newYork).description == "2025-12-29")
        #expect(DayKey(localDay: week.last!, calendar: newYork).description == "2026-01-04")
    }

    @Test func mondayWeekAcrossDaylightSavingChange() {
        // US DST began Sun Mar 8, 2026; every entry must still be a distinct consecutive day.
        let d = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let keys = CalendarMath.mondayWeek(containing: d, calendar: newYork).map { DayKey(localDay: $0, calendar: newYork).description }
        #expect(keys == ["2026-03-02", "2026-03-03", "2026-03-04", "2026-03-05", "2026-03-06", "2026-03-07", "2026-03-08"])
    }
}
