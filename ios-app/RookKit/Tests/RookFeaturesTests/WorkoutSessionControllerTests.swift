import Foundation
import Testing
import RookLiveActivityKit
import RookModels
import RookNetworking
import RookSession
@testable import RookFeatures

final class FakeLiveActivity: LiveActivityControlling, @unchecked Sendable {
    let events = Locked<[String]>([])
    let lastState = Locked<WorkoutActivityAttributes.ContentState?>(nil)
    var running: Set<String> = []

    func start(workoutId: String, state: WorkoutActivityAttributes.ContentState) async {
        events.mutate { $0.append("start:\(workoutId)") }
        lastState.set(state)
    }
    func update(workoutId: String, state: WorkoutActivityAttributes.ContentState) async {
        events.mutate { $0.append("update:\(state.exerciseName)") }
        lastState.set(state)
    }
    func end(workoutId: String) async { events.mutate { $0.append("end:\(workoutId)") } }
    func endAll(except workoutId: String?) async { events.mutate { $0.append("endAll:\(workoutId ?? "-")") } }
    func isRunning(workoutId: String) async -> Bool { running.contains(workoutId) }
}

final class MemorySessionStore: SessionStoring, @unchecked Sendable {
    let saved = Locked<WorkoutSessionState?>(nil)
    let saves = Locked(0)
    func load() -> WorkoutSessionState? { saved.get() }
    func save(_ state: WorkoutSessionState) throws { saved.set(state); saves.mutate { $0 += 1 } }
    func clear() throws { saved.set(nil) }
}

private let start = Date(timeIntervalSince1970: 1_773_500_000)

private func serverWorkout() -> WorkoutInstance {
    WorkoutInstance(
        workoutInstanceId: "w1", status: .inProgress, startedAt: start, gymName: "Garage",
        exercises: [
            WorkoutExercise(exerciseId: "bench", exerciseName: "Bench", modality: .setsReps, sets: 3, reps: 8, orderIndex: 0, lastUsedWeight: 135),
            WorkoutExercise(exerciseId: "plank", exerciseName: "Plank", modality: .duration, durationSeconds: 30, orderIndex: 1),
            WorkoutExercise(exerciseId: "row", exerciseName: "Row", modality: .setsReps, orderIndex: 2),
        ]
    )
}

@MainActor
@Suite("Workout session controller")
struct WorkoutSessionControllerTests {
    let api = FakeAPI()
    let store = MemorySessionStore()
    let live = FakeLiveActivity()
    let clock = MutableClock(start)
    let expired = Locked(0)

    func makeController(unit: WeightUnit = .lbs) -> WorkoutSessionController {
        WorkoutSessionController(
            api: api, store: store, liveActivity: live, unit: unit, clock: clock.clock,
            sleep: { _ in }, autosaveDelay: .zero
        ) { [expired] in expired.mutate { $0 += 1 } }
    }

    @Test func beginPersistsAndStartsLiveActivity() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        #expect(c.isActive)
        #expect(store.saved.get()?.workoutId == "w1")
        #expect(live.events.get() == ["endAll:-", "start:w1"])
        #expect(live.lastState.get()?.workoutName == "Garage")
        #expect(live.lastState.get()?.exerciseName == "Bench")
    }

    @Test func navigationUpdatesLiveActivityButDoesNotAutosave() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        await c.goToNext()
        await c.goToPrevious()
        await c.goToPrevious() // no-op at the first exercise: nothing sent
        #expect(live.events.get().suffix(2) == ["update:Plank", "update:Bench"])
        await c.waitForAutosave()
        #expect(api.count(.update) == 0)
    }

    @Test func loggingWeightAutosavesExercises() async {
        let c = makeController(unit: .kg)
        await c.begin(with: serverWorkout())
        await c.setWeight(60)
        await c.waitForAutosave()
        #expect(c.session?.exercises[0].weight == 60)
        #expect(c.session?.exercises[0].weightUnit == .kg)
        #expect(api.calls.get().last == "update:progress")
        #expect(api.workoutUpdates.get().last?.1.exercises?.first?.weight == 60)
        #expect(c.syncStatus == .synced)
        #expect(live.lastState.get()?.weightDescription == "60 kg")
    }

    @Test func failedAutosaveIsRetriedLater() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        api.fail(.update, with: APIError.network(.notConnectedToInternet))
        await c.setWeight(100)
        await c.waitForAutosave()
        #expect(c.syncStatus == .pending)
        api.succeed(.update)
        await c.sceneDidBecomeActive()
        await c.waitForAutosave()
        #expect(c.syncStatus == .synced)
        #expect(api.count(.update) == 2)
    }

    @Test func pausingFreezesTheLiveActivity() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        clock.advance(90)
        await c.togglePause()
        #expect(c.session?.isPaused == true)
        #expect(live.lastState.get()?.isPaused == true)
        #expect(live.lastState.get()?.pausedElapsedSeconds == 90)
        clock.advance(30)
        await c.togglePause()
        #expect(live.lastState.get()?.timerReference == start.addingTimeInterval(30))
    }

    @Test func durationExerciseFlow() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        await c.goToNext()
        await c.toggleDuration()
        #expect(live.lastState.get()?.durationEnd == clock.now.addingTimeInterval(30))
        clock.advance(10)
        await c.toggleDuration()
        #expect(live.lastState.get()?.durationRemaining == 20)
        await c.completeDuration()
        #expect(c.session?.exercises[1].weight == 0)
        #expect(c.session?.currentIndex == 2)
        await c.waitForAutosave()
        #expect(api.count(.update) == 1)
    }

    @Test func skipAdvances() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        await c.skipCurrent()
        #expect(c.session?.exercises[0].skipped == true)
        #expect(c.session?.currentIndex == 1)
    }

    @Test func completeSucceedsAndCleansUp() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        #expect(await c.complete() == false) // not every exercise is logged yet
        await c.setWeight(135)
        await c.goToNext()
        await c.goToNext()
        await c.skipCurrent()
        #expect(await c.complete())
        #expect(!c.isActive)
        #expect(store.saved.get() == nil)
        #expect(live.events.get().last == "end:w1")
        let completion = api.workoutUpdates.get().last!.1
        #expect(completion.status == .completed)
        #expect(completion.exercises?.count == 3)
    }

    @Test func completeFailureKeepsWorkout() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        await c.setWeight(135)
        await c.goToNext(); await c.goToNext()
        await c.skipCurrent()
        api.fail(.update, with: APIError.server(status: 503))
        #expect(await c.complete() == false)
        #expect(c.isActive)
        #expect(c.finishError?.contains("kept on this phone") == true)
        #expect(store.saved.get() != nil)
        api.succeed(.update)
        #expect(await c.complete())
    }

    @Test func completingAnAlreadyFinishedWorkoutClearsIt() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        await c.setWeight(135)
        await c.goToNext(); await c.goToNext()
        await c.skipCurrent()
        api.fail(.update, with: APIError.rejected(status: 400, message: "Cannot modify completed or cancelled workout"))
        #expect(await c.complete())
        #expect(!c.isActive)
    }

    @Test func cancelAndDiscard() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        api.fail(.update, with: APIError.network(.timedOut))
        #expect(await c.cancel() == false)
        #expect(c.isActive)
        #expect(c.finishError != nil)
        await c.discardLocally()
        #expect(!c.isActive)
        #expect(live.events.get().last == "end:w1")

        api.succeed(.update)
        await c.begin(with: serverWorkout())
        #expect(await c.cancel())
        #expect(api.workoutUpdates.get().last?.1.status == .cancelled)
    }

    @Test func expiredSessionDuringSave() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        api.fail(.update, with: APIError.unauthorized)
        await c.setWeight(1)
        await c.waitForAutosave()
        #expect(expired.get() == 1)
    }

    @Test func restoreResumesOrCleansUp() async {
        let c = makeController()
        await c.restore()
        #expect(!c.isActive)
        #expect(live.events.get() == ["endAll:-"])

        store.saved.set(WorkoutSessionState(workout: serverWorkout()))
        let resumed = makeController()
        await resumed.restore()
        #expect(resumed.session?.workoutId == "w1")
        #expect(live.events.get().suffix(2) == ["endAll:w1", "start:w1"])

        live.running = ["w1"]
        let again = makeController()
        await again.restore()
        #expect(live.events.get().last == "update:Bench")
    }

    @Test func advanceFromLiveActivityStopsAtLast() async {
        let c = makeController()
        await c.begin(with: serverWorkout())
        await c.advanceFromLiveActivity()
        await c.advanceFromLiveActivity()
        await c.advanceFromLiveActivity()
        #expect(c.session?.currentIndex == 2)
    }
}
