import Foundation
import RookModels
import RookNetworking
import Testing
@testable import RookFeatures

@Suite("Sauna")
struct SaunaTests {
    @Test func recognisesSaunaExercisesAndWorkouts() {
        #expect(Sauna.isSauna(Sauna.exercise(minutes: 10)))
        #expect(Sauna.isSauna(WorkoutExercise(exerciseId: "other-id", exerciseName: " sauna ", modality: .duration)))
        #expect(!Sauna.isSauna(WorkoutExercise(exerciseId: "core-plank", exerciseName: "Plank", modality: .duration)))

        let bench = WorkoutExercise(exerciseId: "bench", exerciseName: "Bench Press", modality: .setsReps)
        let sauna = WorkoutInstance.completed("s", completedAt: dashNow, exercises: [Sauna.exercise(minutes: 20)])
        let mixed = WorkoutInstance.completed("m", completedAt: dashNow, exercises: [bench, Sauna.exercise(minutes: 20)])
        var skippedLift = mixed
        skippedLift.exercises[0].skipped = true
        #expect(Sauna.isSaunaWorkout(sauna))
        #expect(!Sauna.isSaunaWorkout(mixed))
        #expect(Sauna.isSaunaWorkout(skippedLift))
        #expect(!Sauna.isSaunaWorkout(.completed("e", completedAt: dashNow, exercises: [])))
    }

    @Test func exerciseShape() {
        let exercise = Sauna.exercise(minutes: 25)
        #expect(exercise.exerciseId == "recovery-sauna")
        #expect(exercise.exerciseName == "Sauna")
        #expect(exercise.modality == .duration)
        #expect(exercise.sets == 1)
        #expect(exercise.durationSeconds == 1_500)
        #expect(exercise.isReadyForCompletion)
    }

    @Test func presentationUsesSessionMinutes() {
        // Logged sessions are created and completed together, so the server's durationMinutes is ~0.
        let sauna = WorkoutInstance.completed("s", completedAt: dashNow, minutes: 0, exercises: [Sauna.exercise(minutes: 20)])
        #expect(Sauna.minutes(in: sauna) == 20)
        #expect(WorkoutPresentation.minutes(for: sauna) == 20)
        #expect(WorkoutPresentation.detail(for: Sauna.exercise(minutes: 15), fallbackUnit: .lbs) == "15 min")
        #expect(WorkoutPresentation.title(for: sauna) == "Sauna")
    }
}

@MainActor
@Suite("Sauna logging")
struct SaunaLogModelTests {
    let api = FakeAPI()
    let expired = Locked(0)

    func makeModel(gym: Gym? = nil) -> SaunaLogModel {
        SaunaLogModel(api: api, gym: gym) { [expired] in expired.mutate { $0 += 1 } }
    }

    @Test func minutesAreClamped() {
        let model = makeModel()
        #expect(model.minutes == 20)
        model.minutes = 0
        #expect(model.minutes == 1)
        model.minutes = 500
        #expect(model.minutes == 180)
    }

    @Test func logsACompletedSaunaWorkout() async throws {
        let model = makeModel(gym: Gym(gymId: "g1", name: "Home", equipmentTypes: []))
        model.minutes = 25
        let logged = await model.log()
        #expect(logged?.status == .completed)
        #expect(api.calls.get() == ["create", "update:completed"])

        let request = try #require(api.createdWorkouts.get().first)
        #expect(request.exercises == [Sauna.exercise(minutes: 25)])
        #expect(request.source == .manual)
        #expect(request.gymId == "g1")
        #expect(request.gymName == "Home")
        let (id, update) = try #require(api.workoutUpdates.get().first)
        #expect(id == "w-new")
        #expect(update == .complete([Sauna.exercise(minutes: 25)]))
        #expect(model.errorMessage == nil)
        #expect(!model.isSaving)
    }

    @Test func createFailureShowsError() async {
        api.fail(.create, with: APIError.network(.notConnectedToInternet))
        let model = makeModel()
        #expect(await model.log() == nil)
        #expect(model.errorMessage?.contains("offline") == true)
        #expect(api.count(.update) == 0)
    }

    @Test func completeFailureCancelsTheCreatedWorkout() async {
        api.fail(.update, with: APIError.server(status: 500))
        let model = makeModel()
        #expect(await model.log() == nil)
        #expect(model.errorMessage != nil)
        #expect(api.calls.get() == ["create", "update:completed", "update:cancelled"])
    }

    @Test func expiredSessionSignsOut() async {
        api.fail(.create, with: APIError.unauthorized)
        let model = makeModel()
        #expect(await model.log() == nil)
        #expect(expired.get() == 1)
        #expect(model.errorMessage == nil)
    }
}
