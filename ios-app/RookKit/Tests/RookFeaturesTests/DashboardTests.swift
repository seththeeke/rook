import Foundation
import Testing
import RookFormatting
import RookModels
import RookNetworking
@testable import RookFeatures

/// Saturday 2026-03-14 12:00 in New York.
let dashNow = ISO8601.parse("2026-03-14T16:00:00Z")!
let nyCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    return cal
}()

func daysAgo(_ days: Double) -> Date { dashNow.addingTimeInterval(-days * 86_400) }

@Suite("Completed workout pager")
struct PagerTests {
    @Test func skipsNonCompletedAndPagesUntilEnough() async throws {
        let api = FakeAPI()
        api.workoutPages = [
            nil: WorkoutListPage(items: [
                WorkoutInstance(workoutInstanceId: "live", status: .inProgress, startedAt: daysAgo(0), exercises: []),
                WorkoutInstance(workoutInstanceId: "x", status: .cancelled, startedAt: daysAgo(1), exercises: []),
            ], nextToken: "p2"),
            "p2": WorkoutListPage(items: [.completed("a", completedAt: daysAgo(2)), .completed("b", completedAt: daysAgo(3))], nextToken: "p3"),
            "p3": WorkoutListPage(items: [.completed("b", completedAt: daysAgo(3)), .completed("c", completedAt: daysAgo(40))], nextToken: nil),
        ]
        var pager = CompletedWorkoutPager()
        try await pager.load(api: api, minimumCount: 2)
        #expect(pager.workouts.map(\.id) == ["a", "b"])
        #expect(!pager.isExhausted)
        try await pager.load(api: api, minimumCount: 10)
        #expect(pager.workouts.map(\.id) == ["a", "b", "c"]) // deduped "b"
        #expect(pager.isExhausted)
        #expect(try await pager.loadNextPage(api: api) == 0)
        #expect(api.calls.get() == ["workouts", "workouts:p2", "workouts:p3"])
    }

    @Test func coversCutoffAndRespectsPageCap() async throws {
        let api = FakeAPI()
        api.workoutPages = [
            nil: WorkoutListPage(items: [.completed("a", completedAt: daysAgo(5))], nextToken: "p2"),
            "p2": WorkoutListPage(items: [.completed("b", completedAt: daysAgo(20))], nextToken: "p3"),
            "p3": WorkoutListPage(items: [.completed("c", completedAt: daysAgo(31))], nextToken: "p4"),
        ]
        var pager = CompletedWorkoutPager()
        try await pager.load(api: api, coveringBack: daysAgo(30))
        #expect(pager.workouts.count == 3)
        var capped = CompletedWorkoutPager()
        try await capped.load(api: api, coveringBack: daysAgo(30), maxPages: 1)
        #expect(capped.workouts.count == 1)
    }
}

@Suite("Workout presentation")
struct PresentationTests {
    @Test func titles() {
        let ex = { (name: String) in WorkoutExercise(exerciseId: name, exerciseName: name, modality: .setsReps) }
        let w = { (names: [String]) in WorkoutInstance(workoutInstanceId: "w", status: .completed, startedAt: dashNow, gymName: "Garage", exercises: names.map(ex)) }
        #expect(WorkoutPresentation.title(for: w(["Bench Press", "Back Squat"])) == "Bench, Back")
        #expect(WorkoutPresentation.title(for: w(["A", "B", "C", "D", "E"])) == "A, B, C +2")
        #expect(WorkoutPresentation.title(for: w([])) == "Garage")
    }

    @Test func exerciseDetails() {
        var e = WorkoutExercise(exerciseId: "b", exerciseName: "Bench", modality: .setsReps, sets: 3, reps: 8, weight: 135, weightUnit: .lbs)
        #expect(WorkoutPresentation.detail(for: e, fallbackUnit: .kg) == "3 × 8 @ 135 lbs")
        e.weight = 0
        #expect(WorkoutPresentation.detail(for: e, fallbackUnit: .kg) == "3 × 8 · Bodyweight")
        e.weight = nil
        #expect(WorkoutPresentation.detail(for: e, fallbackUnit: .kg) == "3 × 8")
        e.skipped = true
        #expect(WorkoutPresentation.detail(for: e, fallbackUnit: .kg) == "Skipped")
        let plank = WorkoutExercise(exerciseId: "p", exerciseName: "Plank", modality: .duration, durationSeconds: 45)
        #expect(WorkoutPresentation.detail(for: plank, fallbackUnit: .lbs) == "45 s")
        let noUnit = WorkoutExercise(exerciseId: "r", exerciseName: "Row", modality: .setsReps, weight: 60)
        #expect(WorkoutPresentation.detail(for: noUnit, fallbackUnit: .kg) == "3 × 8 @ 60 kg")
    }

    @Test func minutesAndVolume() {
        var w = WorkoutInstance.completed("w", completedAt: dashNow, minutes: 50, volume: 2000)
        #expect(WorkoutPresentation.minutes(for: w) == 50)
        #expect(WorkoutPresentation.volume(for: w) == 2000)
        w.durationMinutes = nil
        w.totalVolume = nil
        #expect(WorkoutPresentation.minutes(for: w) == 50)
        #expect(WorkoutPresentation.volume(for: w) == 2400) // 3 × 8 × 100
    }
}

@MainActor
@Suite("Dashboard")
struct DashboardModelTests {
    let api = FakeAPI()
    let expired = Locked(0)

    func makeModel() -> DashboardModel {
        DashboardModel(api: api, unit: .lbs, clock: Clock { dashNow }, calendar: nyCalendar) { [expired] in
            expired.mutate { $0 += 1 }
        }
    }

    @Test func emptyAccount() async {
        let model = makeModel()
        await model.load()
        #expect(model.state == .loaded)
        #expect(!model.hasAnyWorkouts)
        #expect(model.stats == .init(totalWorkouts: 0, workoutsLast30Days: 0, volumeLast30Days: 0, minutesLast30Days: 0))
        #expect(model.personalRecords.isEmpty)
        #expect(model.recentWorkouts.isEmpty)
        #expect(model.currentWeek.count == 7)
    }

    @Test func thirtyDayFiguresOnlyCountTheLast30Days() async {
        api.global = GlobalMetrics(totalWorkouts: 40, currentStreak: 2, longestStreak: 9, workoutsLast30: 99)
        api.workoutPages = [nil: WorkoutListPage(items: [
            .completed("a", completedAt: daysAgo(1), minutes: 30, volume: 1000),
            .completed("b", completedAt: daysAgo(29), minutes: 40, volume: 2000),
            .completed("c", completedAt: daysAgo(31), minutes: 50, volume: 4000),
        ], nextToken: nil)]
        let model = makeModel()
        await model.load()
        #expect(model.stats == .init(totalWorkouts: 40, workoutsLast30Days: 2, volumeLast30Days: 3000, minutesLast30Days: 70))
        #expect(model.recentWorkouts.map(\.id) == ["a", "b", "c"])
    }

    @Test func personalRecordsCompareAcrossUnits() async {
        api.exerciseMetrics = [
            ExerciseMetricsSummary(exerciseId: "squat", exerciseName: "Squat", totalSessions: 5, maxWeight: 200, maxWeightUnit: .lbs),
            ExerciseMetricsSummary(exerciseId: "dead", exerciseName: "Deadlift", totalSessions: 3, maxWeight: 100, maxWeightUnit: .kg), // 220 lbs
            ExerciseMetricsSummary(exerciseId: "plank", exerciseName: "Plank", totalSessions: 9, maxWeight: 0),
            ExerciseMetricsSummary(exerciseId: "curl", exerciseName: "Curl", totalSessions: 2, maxWeight: 40),
        ]
        let model = makeModel()
        await model.load()
        #expect(model.personalRecords.map(\.id) == ["dead", "squat", "curl"])
        #expect(model.personalRecords[0].unit == .kg)
        #expect(model.personalRecords[2].unit == .lbs) // falls back to the profile unit
    }

    @Test func weekStripMarksUTCDaysAndToday() async {
        api.global = GlobalMetrics(totalWorkouts: 2, completedDates: ["2026-03-09", "2026-03-14", "bad"])
        let model = makeModel()
        await model.load()
        let week = model.currentWeek
        #expect(week.map(\.key.description) == ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12", "2026-03-13", "2026-03-14", "2026-03-15"])
        #expect(week.filter(\.hasWorkout).map(\.letter) == ["M", "S"])
        #expect(week.first { $0.isToday }?.key.description == "2026-03-14")
    }

    @Test func failureThenRetry() async {
        api.fail(.global, with: APIError.network(.notConnectedToInternet))
        let model = makeModel()
        await model.load()
        #expect(model.state == .failed(APIError.network(.notConnectedToInternet).userMessage))
        api.succeed(.global)
        await model.load()
        #expect(model.state == .loaded)
    }

    @Test func refreshFailureKeepsData() async {
        api.global = GlobalMetrics(totalWorkouts: 3)
        let model = makeModel()
        await model.load()
        api.fail(.exerciseMetrics, with: APIError.server(status: 500))
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.refreshError != nil)
        #expect(model.global.totalWorkouts == 3)
        #expect(!model.isRefreshing)
    }

    @Test func expiredSession() async {
        api.fail(.workouts, with: APIError.unauthorized)
        await makeModel().load()
        #expect(expired.get() == 1)
    }
}

@MainActor
@Suite("History")
struct HistoryModelTests {
    @Test func loadsPagesAndStopsAtEnd() async {
        let api = FakeAPI()
        api.workoutPages = [
            nil: WorkoutListPage(items: (0..<25).map { .completed("a\($0)", completedAt: daysAgo(Double($0))) }, nextToken: "p2"),
            "p2": WorkoutListPage(items: (0..<10).map { .completed("b\($0)", completedAt: daysAgo(Double(30 + $0))) }, nextToken: nil),
        ]
        let model = HistoryModel(api: api) {}
        await model.loadFirstPage()
        #expect(model.workouts.count == 25)
        #expect(!model.reachedEnd)
        await model.loadFirstPage() // idempotent
        #expect(api.count(.workouts) == 1)
        await model.loadMoreIfNeeded(currentId: "a3") // not the last row
        #expect(api.count(.workouts) == 1)
        await model.loadMoreIfNeeded(currentId: model.workouts.last!.id)
        #expect(model.workouts.count == 35)
        #expect(model.reachedEnd)
    }

    @Test func errorsAndRetry() async {
        let api = FakeAPI()
        api.fail(.workouts, with: APIError.network(.timedOut))
        let model = HistoryModel(api: api) {}
        await model.loadFirstPage()
        #expect(model.errorMessage != nil)
        api.succeed(.workouts)
        await model.retry()
        #expect(model.errorMessage == nil)
        #expect(model.reachedEnd)
    }

    @Test func expiredSession() async {
        let api = FakeAPI()
        api.fail(.workouts, with: APIError.unauthorized)
        let expired = Locked(false)
        let model = HistoryModel(api: api) { expired.set(true) }
        await model.loadFirstPage()
        #expect(expired.get())
    }
}
