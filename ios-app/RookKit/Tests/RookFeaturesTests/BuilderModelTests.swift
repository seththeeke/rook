import Foundation
import Testing
import RookModels
import RookNetworking
@testable import RookFeatures

/// Scripted AI stream: replays `events`, then finishes or throws `error`. `hang` never completes
/// (to test cancellation).
final class FakeAIStream: AIWorkoutStreaming, @unchecked Sendable {
    var events: [AIStreamEvent] = []
    var error: Error?
    var hang = false
    let generated = Locked<[AIGenerateRequest]>([])
    let regenerated = Locked<[AIRegenerateRequest]>([])

    func generate(_ request: AIGenerateRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        generated.mutate { $0.append(request) }
        return replay()
    }

    func regenerate(_ request: AIRegenerateRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        regenerated.mutate { $0.append(request) }
        return replay()
    }

    private func replay() -> AsyncThrowingStream<AIStreamEvent, Error> {
        let events = events, error = error, hang = hang
        return AsyncThrowingStream { continuation in
            let task = Task {
                for event in events { continuation.yield(event) }
                if hang {
                    try? await Task.sleep(for: .seconds(3600))
                    continuation.finish(throwing: CancellationError())
                    return
                }
                if let error { continuation.finish(throwing: error) } else { continuation.finish() }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

let bench = ExerciseCatalogItem(exerciseId: "bench", name: "Bench Press", muscleGroups: ["chest"], muscleGroup: "chest", modality: .setsReps, defaultSets: 4, defaultReps: 6)
let row = ExerciseCatalogItem(exerciseId: "row", name: "Barbell Row", muscleGroups: ["back"], muscleGroup: "back", modality: .setsReps)
let plank = ExerciseCatalogItem(exerciseId: "plank", name: "Plank", muscleGroups: ["core"], muscleGroup: "core", modality: .duration, defaultDurationSeconds: 45)

@MainActor
@Suite("Builder")
struct BuilderModelTests {
    let api = FakeAPI()
    let ai = FakeAIStream()
    let expired = Locked(0)

    func makeModel(unit: WeightUnit = .lbs) -> BuilderModel {
        let counter = Locked(0)
        return BuilderModel(
            api: api, aiStream: ai, unit: unit,
            search: ExerciseSearchModel(api: api),
            makeSessionId: { "session-\(counter.mutate { $0 += 1; return $0 })" }
        ) { [expired] in expired.mutate { $0 += 1 } }
    }

    // MARK: Gyms

    @Test func preselectsDefaultGym() async {
        api.gyms = GymsListResponse(gyms: [Gym(gymId: "g1", name: "Home", equipmentTypes: ["dumbbells"]), Gym(gymId: "g2", name: "Club", equipmentTypes: [])], defaultGymId: "g2")
        let model = makeModel()
        await model.loadGyms()
        #expect(model.selectedGym?.name == "Club")
        model.selectedGymId = "g1"
        await model.loadGyms() // keeps the user's choice
        #expect(model.selectedGym?.name == "Home")
    }

    @Test func gymErrorsDontBlockBuilding() async {
        api.fail(.gyms, with: APIError.server(status: 500))
        let model = makeModel()
        await model.loadGyms()
        #expect(model.gymsError != nil)
        #expect(model.selectedGym == nil)
    }

    // MARK: Manual

    @Test func addRejectsDuplicatesAndUsesCatalogDefaults() {
        let model = makeModel()
        #expect(model.add(bench))
        #expect(!model.add(bench))
        #expect(model.duplicateNotice == "Bench Press is already in this workout.")
        model.add(plank)
        #expect(model.duplicateNotice == nil)
        #expect(model.exercises.map(\.sets) == [4, nil])
        #expect(model.exercises[1].durationSeconds == 45)
        #expect(model.exercises.map(\.orderIndex) == [0, 1])
    }

    @Test func toggleAddsAndRemoves() {
        let model = makeModel()
        model.toggle(bench)
        model.toggle(row)
        model.toggle(bench)
        #expect(model.exercises.map(\.exerciseId) == ["row"])
        #expect(model.exercises[0].orderIndex == 0)
    }

    @Test func editingClampsValues() {
        let model = makeModel()
        model.add(bench)
        model.add(plank)
        model.setSets(0, at: 0)
        model.setReps(500, at: 0)
        model.setDuration(1, at: 1)
        model.setSets(5, at: 9) // out of range: ignored
        #expect(model.exercises[0].sets == 1)
        #expect(model.exercises[0].reps == 100)
        #expect(model.exercises[1].durationSeconds == 5)
    }

    @Test func moveAndRemoveRenumber() {
        let model = makeModel()
        model.add(bench); model.add(row); model.add(plank)
        model.move(from: IndexSet(integer: 0), to: 3)
        #expect(model.exercises.map(\.exerciseId) == ["row", "plank", "bench"])
        model.move(from: IndexSet(integer: 2), to: 0)
        #expect(model.exercises.map(\.exerciseId) == ["bench", "row", "plank"])
        model.remove(at: IndexSet(integer: 1))
        #expect(model.exercises.map(\.exerciseId) == ["bench", "plank"])
        #expect(model.exercises.map(\.orderIndex) == [0, 1])
        model.clear()
        #expect(model.exercises.isEmpty)
        #expect(!model.canStart)
    }

    @Test func swapBlocksDuplicatesButAllowsSameSlot() {
        let model = makeModel()
        model.add(bench); model.add(row)
        #expect(!model.swap(at: 0, with: row))
        #expect(model.swap(at: 0, with: bench))
        #expect(model.swap(at: 1, with: plank))
        #expect(model.exercises.map(\.exerciseId) == ["bench", "plank"])
        #expect(model.exercises[1].orderIndex == 1)
        #expect(!model.swap(at: 7, with: row))
    }

    @Test func loadPastWorkoutCopiesFreshExercises() async {
        api.gyms = GymsListResponse(gyms: [Gym(gymId: "g9", name: "Garage", equipmentTypes: [])], defaultGymId: nil)
        let model = makeModel()
        await model.loadGyms()
        let past = WorkoutInstance(
            workoutInstanceId: "old", status: .completed, startedAt: Date(), gymId: "g9",
            exercises: [
                WorkoutExercise(exerciseId: "row", exerciseName: "Row", modality: .setsReps, sets: 5, reps: 5, weight: 185, weightUnit: .lbs, skipped: true, orderIndex: 1),
                WorkoutExercise(exerciseId: "bench", exerciseName: "Bench", modality: .setsReps, sets: 3, reps: 8, weight: 135, orderIndex: 0),
                WorkoutExercise(exerciseId: "bench", exerciseName: "Bench", modality: .setsReps, orderIndex: 2),
            ]
        )
        model.loadPastWorkout(past)
        #expect(model.exercises.map(\.exerciseId) == ["bench", "row"])
        #expect(model.exercises.allSatisfy { $0.weight == nil && !$0.skipped })
        #expect(model.exercises[1].sets == 5)
        #expect(model.source == .manual)
        #expect(model.selectedGym?.gymId == "g9")
    }

    // MARK: AI

    @Test func generateBuildsDraftFromStream() async {
        api.gyms = GymsListResponse(gyms: [Gym(gymId: "g", name: "Home", equipmentTypes: ["dumbbells"])], defaultGymId: "g")
        ai.events = [
            .progress(step: "analyzing_goals", message: "Analyzing..."),
            .progress(step: "analyzing_goals", message: "Analyzing..."),
            .progress(step: "scanning_catalog", message: "Scanning..."),
            .complete([
                WorkoutExercise(exerciseId: "bench", exerciseName: "Bench", modality: .setsReps),
                WorkoutExercise(exerciseId: "bench", exerciseName: "Bench", modality: .setsReps),
                WorkoutExercise(exerciseId: "plank", exerciseName: "Plank", modality: .duration, skipped: true, orderIndex: 9),
            ]),
        ]
        let model = makeModel(unit: .kg)
        await model.loadGyms()
        #expect(!model.canGenerate)
        model.appendQuickPrompt("Push day")
        model.appendQuickPrompt("30 min quick")
        #expect(model.prompt == "Push day 30 min quick")
        let ok = await model.generate()
        #expect(ok)
        #expect(model.aiProgress == ["Analyzing...", "Scanning..."])
        #expect(model.exercises.map(\.exerciseId) == ["bench", "plank"])
        #expect(model.exercises[0].sets == 3 && model.exercises[0].reps == 8)
        #expect(model.exercises[1].durationSeconds == 60 && !model.exercises[1].skipped)
        #expect(model.exercises.map(\.orderIndex) == [0, 1])
        #expect(model.source == .aiGenerated)
        #expect(model.aiPrompt == "Push day 30 min quick")
        let request = ai.generated.get()[0]
        #expect(request.weightUnit == .kg)
        #expect(request.equipmentTypes == ["dumbbells"])
        #expect(request.builderSessionId == model.builderSessionId)
    }

    @Test func generateReportsServerErrorsAndEmptyResults() async {
        let model = makeModel()
        model.prompt = "Something odd"
        ai.error = AIStreamError.server("No exercises fit your equipment")
        #expect(await model.generate() == false)
        #expect(model.aiError == "No exercises fit your equipment")

        ai.error = nil
        ai.events = [.complete([])]
        #expect(await model.generate() == false)
        #expect(model.aiError?.contains("No exercises matched") == true)

        ai.events = []
        #expect(await model.generate() == false)
        #expect(model.aiError == AIStreamError.incomplete.userMessage)
        #expect(!model.isGenerating)
    }

    @Test func generateWithExpiredSession() async {
        ai.error = AIStreamError.unauthorized
        let model = makeModel()
        model.prompt = "Legs"
        _ = await model.generate()
        #expect(expired.get() == 1)
        #expect(model.aiError == nil)
    }

    @Test func cancellingGenerationIsSilent() async {
        ai.hang = true
        ai.events = [.progress(step: "a", message: "Working")]
        let model = makeModel()
        model.prompt = "Legs"
        let task = Task { await model.generate() }
        while model.aiProgress.isEmpty { await Task.yield() }
        model.cancelGeneration()
        #expect(await task.value == false)
        #expect(model.aiError == nil)
        #expect(model.exercises.isEmpty)
    }

    @Test func regenerateSendsContextForSelection() async {
        api.exercises = [bench, row, plank]
        ai.events = [.complete([
            WorkoutExercise(exerciseId: "bench", exerciseName: "Bench", modality: .setsReps),
            WorkoutExercise(exerciseId: "fly", exerciseName: "Fly", modality: .setsReps),
        ])]
        let model = makeModel()
        model.prompt = "Push"
        _ = await model.generate()
        ai.events = [.complete([
            WorkoutExercise(exerciseId: "bench", exerciseName: "Bench", modality: .setsReps),
            WorkoutExercise(exerciseId: "dip", exerciseName: "Dip", modality: .setsReps),
        ])]
        #expect(!model.canRegenerate)
        model.toggleRegenerateSelection(1)
        model.toggleRegenerateSelection(0)
        model.toggleRegenerateSelection(0)
        await model.regenerateSelected()
        #expect(model.exercises.map(\.exerciseId) == ["bench", "dip"])
        #expect(model.selectedForRegenerate.isEmpty)
        let context = ai.regenerated.get()[0].regenerateContext
        #expect(context.exerciseIndices == [1])
        #expect(context.currentExerciseIds == ["bench", "fly"])
        #expect(context.targetMuscleGroups == ["full"]) // "fly" isn't in the catalog
        #expect(context.userPrompt == "Push")
        #expect(ai.regenerated.get()[0].builderSessionId == ai.generated.get()[0].builderSessionId)
    }

    @Test func regenerateUsesCatalogMuscleGroupsAndReportsErrors() async {
        api.exercises = [bench, row]
        ai.events = [.complete([WorkoutExercise(exerciseId: "row", exerciseName: "Row", modality: .setsReps)])]
        let model = makeModel()
        model.prompt = "Pull"
        _ = await model.generate()
        model.toggleRegenerateSelection(0)
        ai.error = AIStreamError.http(status: 502)
        ai.events = []
        await model.regenerateSelected()
        #expect(ai.regenerated.get()[0].regenerateContext.targetMuscleGroups == ["back"])
        #expect(model.regenerateError != nil)
        #expect(model.exercises.map(\.exerciseId) == ["row"])
    }

    @Test func manualEditsOfAIDraftBecomeManual() async {
        ai.events = [.complete([WorkoutExercise(exerciseId: "row", exerciseName: "Row", modality: .setsReps)])]
        let model = makeModel()
        model.prompt = "Pull"
        _ = await model.generate()
        model.convertToManual()
        #expect(model.source == .manual)
        #expect(!model.canRegenerate)
    }

    // MARK: Start

    @Test func startCreatesWorkoutWithGymAndSource() async {
        api.gyms = GymsListResponse(gyms: [Gym(gymId: "g", name: "Home", equipmentTypes: [])], defaultGymId: "g")
        let model = makeModel()
        await model.loadGyms()
        model.add(bench)
        model.add(plank)
        let workout = await model.startWorkout()
        #expect(workout?.workoutInstanceId == "w-new")
        let request = api.createdWorkouts.get()[0]
        #expect(request.source == .manual)
        #expect(request.gymId == "g" && request.gymName == "Home")
        #expect(request.permissionType == .followersOnly)
        #expect(request.exercises.map(\.orderIndex) == [0, 1])
    }

    @Test func startFailureShowsError() async {
        api.fail(.create, with: APIError.server(status: 502))
        let model = makeModel()
        model.add(bench)
        #expect(await model.startWorkout() == nil)
        #expect(model.startError?.contains("Couldn't start") == true)
        #expect(!model.isStarting)
        #expect(await makeModel().startWorkout() == nil) // empty draft
    }
}

@MainActor
@Suite("Exercise search")
struct ExerciseSearchModelTests {
    let hackSquat = ExerciseCatalogItem(
        exerciseId: "quads-hack-squat", name: "Hack Squat", muscleGroups: ["quads", "glutes"], muscleGroup: "quads",
        equipment: ["hack squat machine"], equipmentPrimary: "machine", modality: .setsReps
    )
    let retired = ExerciseCatalogItem(exerciseId: "old", name: "Old Squat", muscleGroup: "quads", modality: .setsReps, isActive: false)

    @Test func catalogMuscleGroupsMatchStoredValues() {
        let values = ExerciseSearchModel.muscleGroups.map(\.value)
        #expect(values.contains("quads"))
        #expect(!values.contains("quadriceps"))
        #expect(values.contains("full body"))
    }

    @Test(arguments: ["machine hack squat", "Hack", "squat machine", "QUADS hack", "hack-squat", ""])
    func findsHackSquat(query: String) {
        #expect(ExerciseSearchModel.matches(hackSquat, query: query))
    }

    @Test(arguments: ["barbell hack squat", "bench", "smith"])
    func rejectsNonMatches(query: String) {
        #expect(!ExerciseSearchModel.matches(hackSquat, query: query))
    }

    @Test func filtersLocallyAndByMuscleGroup() async {
        let api = FakeAPI()
        api.exercises = [bench, row, plank, hackSquat, retired]
        let model = ExerciseSearchModel(api: api)
        await model.loadIfNeeded()
        #expect(model.results.map(\.exerciseId) == ["row", "bench", "quads-hack-squat", "plank"]) // sorted, inactive hidden
        model.query = "machine hack squat"
        #expect(model.results.map(\.exerciseId) == ["quads-hack-squat"])
        model.query = ""
        model.muscleGroup = "back"
        await model.waitForSearch()
        #expect(model.results.map(\.exerciseId) == ["row"])
        // Typing never sends the phrase to the server (its search is whole-phrase only).
        #expect(api.exerciseQueries.get().allSatisfy { $0.1 == nil })
    }

    @Test func errorsAndRetry() async {
        let api = FakeAPI()
        api.fail(.exercises, with: APIError.network(.notConnectedToInternet))
        let model = ExerciseSearchModel(api: api)
        await model.loadIfNeeded()
        #expect(model.errorMessage != nil)
        api.succeed(.exercises)
        api.exercises = [bench]
        model.retry()
        await model.waitForSearch()
        #expect(model.errorMessage == nil)
        #expect(model.results.count == 1)
    }
}

@MainActor
@Suite("Builder quick start")
struct BuilderQuickStartTests {
    let api = FakeAPI()

    func makeModel() -> BuilderModel {
        BuilderModel(api: api, aiStream: FakeAIStream(), unit: .lbs, search: ExerciseSearchModel(api: api)) {}
    }

    private func workout(_ id: String, _ exerciseIds: [String], daysAgo: Double) -> WorkoutInstance {
        .completed(id, completedAt: Date(timeIntervalSince1970: 1_773_500_000 - daysAgo * 86_400), exercises: exerciseIds.enumerated().map { i, ex in
            WorkoutExercise(exerciseId: ex, exerciseName: ex.capitalized, modality: .setsReps, sets: 4, reps: 6, weight: 100, weightUnit: .lbs, orderIndex: i)
        })
    }

    @Test func listsRecentDistinctWorkouts() async {
        api.workoutPages = [nil: WorkoutListPage(items: [
            workout("push-2", ["bench", "press"], daysAgo: 1),
            workout("legs", ["squat"], daysAgo: 2),
            workout("push-1", ["bench", "press"], daysAgo: 4), // same routine as push-2
            workout("reordered", ["press", "bench"], daysAgo: 5), // different order: distinct
            WorkoutInstance(workoutInstanceId: "empty", status: .completed, startedAt: Date(), completedAt: Date(timeIntervalSince1970: 1_773_000_000), exercises: []),
        ], nextToken: nil)]
        let model = makeModel()
        await model.loadRecentWorkouts(limit: 5)
        #expect(model.recentWorkouts.map(\.id) == ["push-2", "legs", "reordered"])
        await model.loadRecentWorkouts() // loads once
        #expect(api.count(.workouts) == 1)
    }

    @Test func respectsLimit() async {
        api.workoutPages = [nil: WorkoutListPage(items: (0..<8).map { workout("w\($0)", ["ex\($0)"], daysAgo: Double($0)) }, nextToken: nil)]
        let model = makeModel()
        await model.loadRecentWorkouts(limit: 3)
        #expect(model.recentWorkouts.map(\.id) == ["w0", "w1", "w2"])
    }

    @Test func loadFailureHidesListQuietly() async {
        api.fail(.workouts, with: APIError.server(status: 500))
        let model = makeModel()
        await model.loadRecentWorkouts()
        #expect(model.hasLoadedRecent)
        #expect(model.recentWorkouts.isEmpty)
        #expect(model.startError == nil)
    }

    @Test func quickStartCreatesWorkoutFromPastDefinition() async {
        api.gyms = GymsListResponse(gyms: [Gym(gymId: "g", name: "Home", equipmentTypes: [])], defaultGymId: "g")
        let model = makeModel()
        await model.loadGyms()
        let past = workout("push", ["bench", "press"], daysAgo: 1)
        let started = await model.quickStart(past)
        #expect(started?.workoutInstanceId == "w-new")
        #expect(model.quickStartingId == nil)
        let request = api.createdWorkouts.get()[0]
        #expect(request.exercises.map(\.exerciseId) == ["bench", "press"])
        #expect(request.exercises.allSatisfy { $0.sets == 4 && $0.reps == 6 && $0.weight == nil && !$0.skipped })
        #expect(request.source == .manual)
        #expect(request.gymId == "g")
    }

    @Test func quickStartFailureReportsError() async {
        api.fail(.create, with: APIError.network(.notConnectedToInternet))
        let model = makeModel()
        #expect(await model.quickStart(workout("push", ["bench"], daysAgo: 1)) == nil)
        #expect(model.startError?.contains("Couldn't start") == true)
        #expect(model.quickStartingId == nil)
    }
}
