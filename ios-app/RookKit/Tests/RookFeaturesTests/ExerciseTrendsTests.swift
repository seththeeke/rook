import Foundation
import Testing
import RookFormatting
import RookModels
import RookNetworking
@testable import RookFeatures

private func session(_ daysBack: Double, _ weight: Double, unit: WeightUnit? = .lbs, reps: Int? = 8, seconds: Int? = nil, modality: ExerciseModality? = .setsReps) -> ExerciseSession {
    ExerciseSession(completedAt: daysAgo(daysBack), modality: modality, weight: weight, weightUnit: unit, sets: 3, reps: reps, durationSeconds: seconds)
}

@Suite("Trend ranges")
struct TrendRangeTests {
    @Test func startsAndLabels() {
        #expect(TrendRange.allCases.map(\.title) == ["30 Days", "90 Days", "YTD", "All Time"])
        #expect(TrendRange.days30.phrase == "in the past 30 days")
        #expect(TrendRange.days90.phrase == "in the past 90 days")
        #expect(TrendRange.yearToDate.phrase == "this year")
        #expect(TrendRange.allTime.phrase == "yet")
        #expect(TrendRange.days30.id == "days30")
        #expect(TrendRange.days30.start(now: dashNow, calendar: nyCalendar) == nyCalendar.date(byAdding: .day, value: -30, to: dashNow))
        #expect(TrendRange.days90.start(now: dashNow, calendar: nyCalendar) == nyCalendar.date(byAdding: .day, value: -90, to: dashNow))
        // YTD starts at local midnight on Jan 1.
        #expect(TrendRange.yearToDate.start(now: dashNow, calendar: nyCalendar) == ISO8601.parse("2026-01-01T05:00:00Z"))
        #expect(TrendRange.allTime.start(now: dashNow, calendar: nyCalendar) == nil)
    }
}

@Suite("Trend metric")
struct TrendMetricTests {
    @Test func picksWeightThenMinutesThenReps() {
        #expect(TrendMetric.best(for: [session(1, 0), session(2, 50)], unit: .kg) == .weight(.kg))
        #expect(TrendMetric.best(for: [session(1, 0, reps: 12)], unit: .lbs) == .reps)
        #expect(TrendMetric.best(for: [session(1, 0, reps: nil, seconds: 60, modality: .duration)], unit: .lbs) == .minutes)
        #expect(TrendMetric.best(for: [session(1, 0, reps: nil, seconds: 60, modality: nil)], unit: .lbs) == .minutes)
        #expect(TrendMetric.best(for: [], unit: .lbs) == .reps)
    }

    @Test func valuesConvertUnits() {
        #expect(TrendMetric.weight(.lbs).value(of: session(1, 100, unit: .kg)) == 220.5)
        #expect(TrendMetric.weight(.kg).value(of: session(1, 100, unit: .lbs)) == 45.4)
        #expect(TrendMetric.weight(.kg).value(of: session(1, 100, unit: nil)) == 100) // assumes the display unit
        #expect(TrendMetric.reps.value(of: session(1, 0, reps: 12)) == 12)
        #expect(TrendMetric.reps.value(of: session(1, 0, reps: nil)) == nil)
        #expect(TrendMetric.minutes.value(of: session(1, 0, seconds: 90)) == 1.5)
        #expect(TrendMetric.minutes.value(of: session(1, 0)) == nil)
    }

    @Test func formatting() {
        #expect(TrendMetric.weight(.lbs).format(135) == "135 lbs")
        #expect(TrendMetric.reps.format(12) == "12 reps")
        #expect(TrendMetric.minutes.format(1.55) == "1.6 min")
        #expect(TrendMetric.weight(.lbs).formatDelta(20) == "+20 lbs")
        #expect(TrendMetric.weight(.kg).formatDelta(-1.5) == "−1.5 kg")
        #expect(TrendMetric.reps.formatDelta(0) == "±0 reps")
    }
}

@Suite("Trend math")
struct TrendMathTests {
    @Test func pointsSortAndSkipMissingValues() {
        let points = TrendMath.points([session(1, 0, reps: 10), session(3, 0, reps: nil), session(5, 0, reps: 8)], metric: .reps)
        #expect(points.map(\.value) == [8, 10])
        #expect(points[0].id == daysAgo(5))
        #expect(TrendMath.convert(10, from: .lbs, to: .lbs) == 10)
    }

    @Test func visibleFiltersByRange() {
        let points = TrendMath.points([session(100, 95), session(60, 105), session(10, 115)], metric: .weight(.lbs))
        #expect(TrendMath.visible(points, range: .days30, now: dashNow, calendar: nyCalendar).map(\.value) == [115])
        #expect(TrendMath.visible(points, range: .days90, now: dashNow, calendar: nyCalendar).map(\.value) == [105, 115])
        #expect(TrendMath.visible(points, range: .yearToDate, now: dashNow, calendar: nyCalendar).map(\.value) == [105, 115])
        #expect(TrendMath.visible(points, range: .allTime, now: dashNow, calendar: nyCalendar).count == 3)
    }

    /// A 7.5 → 9 lb lateral raise fills its chart just like a 115 → 135 lb bench does.
    @Test func yDomainFitsEachSeries() {
        #expect(TrendMath.yDomain([]) == 0...1)
        let raise = TrendMath.yDomain([7.5, 9])
        #expect(abs(raise.lowerBound - 7.2) < 0.0001 && abs(raise.upperBound - 9.3) < 0.0001)
        #expect(TrendMath.yDomain([115, 135]) == 111...139)
        #expect(TrendMath.yDomain([100, 100]) == 95...105) // flat: ±5%
        #expect(TrendMath.yDomain([5, 5]) == 4...6) // flat and small: ±1
        #expect(TrendMath.yDomain([0, 10]) == 0...12) // never below zero for positive values
        #expect(TrendMath.yDomain([-2, 2]) == -2.8...2.8)
    }

    @Test func xDomain() {
        let points = TrendMath.points([session(40, 95), session(10, 115)], metric: .weight(.lbs))
        let thirty = TrendMath.xDomain(points, range: .days30, now: dashNow, calendar: nyCalendar)
        #expect(thirty == nyCalendar.date(byAdding: .day, value: -30, to: dashNow)!...dashNow)
        #expect(TrendMath.xDomain(points, range: .allTime, now: dashNow, calendar: nyCalendar) == daysAgo(40)...dashNow)
        // A single session today pads a day either side so the point isn't on the edge.
        let single = TrendMath.xDomain([TrendPoint(date: dashNow, value: 1)], range: .allTime, now: dashNow, calendar: nyCalendar)
        #expect(single == daysAgo(1)...daysAgo(-1))
        #expect(TrendMath.xDomain([], range: .allTime, now: dashNow, calendar: nyCalendar) == daysAgo(1)...daysAgo(-1))
    }

    @Test func change() {
        #expect(TrendMath.change([TrendPoint(date: dashNow, value: 5)]) == nil)
        let bench = TrendMath.change([TrendPoint(date: daysAgo(20), value: 115), TrendPoint(date: dashNow, value: 135)])!
        #expect(bench.delta == 20)
        #expect(bench.direction == .up)
        #expect(bench.label(metric: .weight(.lbs)) == "+20 lbs · +17%")
        let raise = TrendChange(first: 7.5, last: 9)
        #expect(raise.label(metric: .weight(.lbs)) == "+1.5 lbs · +20%")
        let small = TrendChange(first: 100, last: 97.5)
        #expect(small.direction == .down)
        #expect(small.label(metric: .weight(.lbs)) == "−2.5 lbs · −2.5%")
        let flat = TrendChange(first: 50, last: 50)
        #expect(flat.direction == .flat)
        #expect(flat.label(metric: .weight(.lbs)) == "±0 lbs · ±0%")
        #expect(TrendChange(first: 0, last: 10).percent == nil)
        #expect(TrendChange(first: 0, last: 10).label(metric: .reps) == "+10 reps")
    }
}

@MainActor
@Suite("Exercise trend model")
struct ExerciseTrendModelTests {
    let api = FakeAPI()
    let expired = Locked(0)
    let cache = ExerciseSessionCache()

    func makeModel(unit: WeightUnit = .lbs) -> ExerciseTrendModel {
        ExerciseTrendModel(
            exerciseId: "bench", exerciseName: "Bench Press", api: api, unit: unit, cache: cache,
            clock: Clock { dashNow }, calendar: nyCalendar
        ) { [expired] in expired.mutate { $0 += 1 } }
    }

    @Test func loadsSortsAndDerives() async {
        api.exerciseSessions["bench"] = [session(10, 135), session(100, 95), session(40, 115), session(20, 125)]
        let model = makeModel()
        #expect(model.state == .loading)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.exerciseName == "Bench Press")
        #expect(model.sessions.map(\.weight) == [95, 115, 125, 135])
        #expect(model.metric == .weight(.lbs))
        #expect(model.range == .days90)
        #expect(model.visiblePoints.map(\.value) == [115, 125, 135])
        #expect(model.change?.delta == 20)
        #expect(model.best == 135)
        #expect(model.latest?.value == 135)
        #expect(model.yDomain == 111...139)
        #expect(model.xDomain.upperBound == dashNow)
        #expect(model.visibleSessions.map(\.weight) == [135, 125, 115])
        model.range = .days30
        #expect(model.visiblePoints.map(\.value) == [125, 135])
        #expect(model.visibleSessions.count == 2)
        model.range = .allTime
        #expect(model.allPoints.count == 4)
        #expect(model.visibleSessions.count == 4)
        #expect(model.now == dashNow)
    }

    @Test func cachedHistoryIsReusedUntilRetry() async {
        api.exerciseSessions["bench"] = [session(1, 100)]
        await makeModel().load()
        let second = makeModel()
        #expect(second.state == .loaded) // filled from the cache immediately
        await second.load()
        #expect(api.count(.sessions) == 1)
        api.exerciseSessions["bench"] = [session(1, 100), session(0, 105)]
        await second.retry()
        #expect(api.count(.sessions) == 2)
        #expect(second.sessions.count == 2)
        cache.removeAll()
        #expect(cache["bench"] == nil)
    }

    @Test func failureAndExpiry() async {
        api.fail(.sessions, with: APIError.server(status: 500))
        let model = makeModel()
        await model.load()
        guard case .failed(let message) = model.state else { Issue.record("expected failure"); return }
        #expect(!message.isEmpty)
        #expect(cache["bench"] == nil)

        api.fail(.sessions, with: APIError.unauthorized)
        await model.retry()
        #expect(expired.get() == 1)
    }

    @Test func unweightedExercisePlotsReps() async {
        api.exerciseSessions["bench"] = [session(5, 0, reps: 8), session(1, 0, reps: 12)]
        let model = makeModel()
        await model.load()
        #expect(model.metric == .reps)
        #expect(model.change?.label(metric: model.metric) == "+4 reps · +50%")
    }
}

@MainActor
@Suite("Dashboard exercise trends")
struct DashboardTrendTests {
    let api = FakeAPI()

    func makeModel(cache: ExerciseSessionCache = ExerciseSessionCache()) -> DashboardModel {
        DashboardModel(api: api, unit: .lbs, clock: Clock { dashNow }, calendar: nyCalendar, sessionCache: cache) {}
    }

    private func summary(
        _ id: String, at: Date? = nil, day: String? = nil, recent: [(Double, Double)] = [], last: Double? = nil, lastUnit: WeightUnit? = nil
    ) -> ExerciseMetricsSummary {
        ExerciseMetricsSummary(
            exerciseId: id, exerciseName: id.capitalized, totalSessions: recent.count, maxWeight: recent.map(\.1).max() ?? last ?? 0,
            maxWeightUnit: .lbs, lastPerformedDate: day, lastPerformedAt: at, lastUsedWeight: last, lastUsedWeightUnit: lastUnit,
            recentSessions: recent.map { RecentSession(completedAt: daysAgo($0.0), weight: $0.1, weightUnit: .lbs, reps: 8) }
        )
    }

    @Test func recentExercisesNewestFirstWithoutSauna() async {
        var many = (0..<12).map { summary("ex\($0)", at: daysAgo(Double(20 + $0)), recent: [(Double(20 + $0), 50)]) }
        many += [
            summary("bench", at: daysAgo(1), recent: [(5, 125), (1, 135)]),
            summary("raise", at: daysAgo(1), recent: [(5, 7.5), (1, 9)]), // same time: ordered by name
            summary("curl", day: "2026-03-12", last: 20, lastUnit: .kg), // older row: no exact time or sessions
            summary(Sauna.exerciseId, at: daysAgo(0), recent: [(0, 0)]),
            summary("ghost"), // no date at all sorts last
            summary("plank", at: daysAgo(400)), // no weight, no sessions
        ]
        api.exerciseMetrics = many
        let model = makeModel()
        await model.load()
        let recent = model.recentExercises
        #expect(recent.count == 10)
        #expect(recent.prefix(3).map(\.id) == ["bench", "raise", "curl"])
        #expect(!recent.contains { $0.id == Sauna.exerciseId || $0.id == "ghost" || $0.id == "plank" })
        #expect(recent[0].latest == 135 && recent[0].delta == 10)
        #expect(recent[1].delta == 1.5)
        #expect(recent[2].latest == 44.1) // lastUsedWeight converted to the profile unit
        #expect(recent[2].delta == nil)
        #expect(recent[2].lastPerformed == ISO8601.parse("2026-03-12T16:00:00Z")) // noon NY on that day
        #expect(recent[2].metric == .weight(.lbs)) // no sessions yet, but a known weight
    }

    @Test func unweightedRowWithoutSessionsUsesReps() async {
        api.exerciseMetrics = [summary("plank", at: daysAgo(1))]
        let model = makeModel()
        await model.load()
        #expect(model.recentExercises.first?.metric == .reps)
        #expect(model.recentExercises.first?.latest == nil)
    }

    @Test func personalRecordsCarrySparklines() async {
        api.exerciseMetrics = [summary("bench", at: daysAgo(1), recent: [(9, 115), (5, 125), (1, 135)])]
        let model = makeModel()
        await model.load()
        #expect(model.personalRecords.first?.trend == [115, 125, 135])
    }

    @Test func loadingClearsTheSessionCache() async {
        let cache = ExerciseSessionCache()
        cache["bench"] = [session(1, 100)]
        await makeModel(cache: cache).load()
        #expect(cache["bench"] == nil)
    }
}
