import Foundation
import Testing
@testable import RookWidgetData

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// Saturday 2026-03-14, 16:00 UTC.
private let now = ISO8601DateFormatter().date(from: "2026-03-14T16:00:00Z")!

@Suite("Widget snapshot")
struct DashboardSnapshotTests {
    let snapshot = DashboardSnapshot(
        updatedAt: now, workoutsLast30Days: 9, saunaSessionsLast30Days: 4,
        days: ["2026-03-09": .workout, "2026-03-12": .sauna, "2026-03-14": .multiple],
        steps: 5_000, stepsDay: "2026-03-14"
    )

    @Test func summaryForToday() {
        let summary = WidgetSummary(snapshot: snapshot, now: now, calendar: utc)
        #expect(summary.hasData)
        #expect(summary.workoutsLast30Days == 9)
        #expect(summary.saunaSessionsLast30Days == 4)
        #expect(summary.steps == 5_000)
        #expect(summary.week.map(\.key) == ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12", "2026-03-13", "2026-03-14", "2026-03-15"])
        #expect(summary.week.map(\.activity) == [.workout, .none, .none, .sauna, .none, .multiple, .none])
        #expect(summary.week.filter(\.isToday).map(\.letter) == ["S"])
    }

    @Test func liveStepsWinOverTheAppsLastValue() {
        #expect(WidgetSummary(snapshot: snapshot, now: now, liveSteps: 6_100, calendar: utc).steps == 6_100)
    }

    @Test func yesterdaysStepsAreNotShownToday() {
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(WidgetSummary(snapshot: snapshot, now: tomorrow, calendar: utc).steps == nil)
    }

    @Test func aNewWeekStartsEmpty() {
        let nextMonday = ISO8601DateFormatter().date(from: "2026-03-16T08:00:00Z")!
        let summary = WidgetSummary(snapshot: snapshot, now: nextMonday, calendar: utc)
        #expect(summary.week.allSatisfy { $0.activity == .none })
        #expect(summary.week.first?.isToday == true)
    }

    @Test func noSnapshot() {
        let summary = WidgetSummary(snapshot: nil, now: now, calendar: utc)
        #expect(!summary.hasData)
        #expect(summary.steps == nil)
        #expect(summary.week.count == 7)
    }

    @Test func sampleHasEveryKindOfDay() {
        let sample = WidgetSummary.sample(now: now, calendar: utc)
        #expect(sample.hasData)
        #expect(Set(sample.week.map(\.activity)) == [.none, .workout, .sauna, .multiple])
    }

    @Test func contentIgnoresTimeAndSteps() {
        var later = snapshot
        later.updatedAt = now.addingTimeInterval(60)
        later.steps = 7_000
        #expect(later.content == snapshot.content)
        later.saunaSessionsLast30Days = 5
        #expect(later.content != snapshot.content)
    }

    @Test func storeRoundTripsAndClears() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        let store = DashboardSnapshotStore(url: url)
        #expect(store.load() == nil)
        store.save(snapshot)
        #expect(store.load() == snapshot)
        store.clear()
        #expect(store.load() == nil)
        // Without an App Group container nothing is stored, and nothing fails.
        let missing = DashboardSnapshotStore(url: nil)
        missing.save(snapshot)
        #expect(missing.load() == nil)
        missing.clear()
    }
}
