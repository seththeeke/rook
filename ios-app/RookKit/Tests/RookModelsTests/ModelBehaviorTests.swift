import Foundation
import Testing
@testable import RookModels

@Suite("Model behavior")
struct ModelBehaviorTests {
    private let bench = ExerciseCatalogItem(
        exerciseId: "bench", name: "Bench", modality: .setsReps, defaultSets: 4, defaultReps: 6
    )
    private let plank = ExerciseCatalogItem(exerciseId: "plank", name: "Plank", modality: .duration)

    @Test func catalogItemUsesItsOwnDefaults() {
        let ex = WorkoutExercise(catalogItem: bench, orderIndex: 2)
        #expect(ex.sets == 4)
        #expect(ex.reps == 6)
        #expect(ex.durationSeconds == nil)
        #expect(ex.orderIndex == 2)
        #expect(ex.skipped == false)
    }

    @Test func catalogItemFallsBackToStandardDefaults() {
        let noDefaults = ExerciseCatalogItem(exerciseId: "x", name: "X", modality: .burnout)
        let ex = WorkoutExercise(catalogItem: noDefaults, orderIndex: 0)
        #expect(ex.sets == 3)
        #expect(ex.reps == 8)

        let timed = WorkoutExercise(catalogItem: plank, orderIndex: 0)
        #expect(timed.durationSeconds == 60)
        #expect(timed.sets == nil)
        #expect(timed.reps == nil)
    }

    @Test(arguments: [
        (ExerciseModality.setsReps, Double?.some(100), Int?.none, false, true),
        (.setsReps, nil, nil, false, false),
        (.burnout, nil, nil, false, false),
        (.duration, nil, 30, false, true),
        (.duration, nil, nil, false, false),
        (.setsReps, nil, nil, true, true),
    ])
    func completionReadiness(
        modality: ExerciseModality, weight: Double?, duration: Int?, skipped: Bool, expected: Bool
    ) {
        let ex = WorkoutExercise(
            exerciseId: "e", exerciseName: "E", modality: modality,
            durationSeconds: duration, weight: weight, skipped: skipped
        )
        #expect(ex.isReadyForCompletion == expected)
    }

    @Test func volumeOnlyCountsCompletedSetsReps() {
        var ex = WorkoutExercise(exerciseId: "e", exerciseName: "E", modality: .setsReps, sets: 3, reps: 10, weight: 50)
        #expect(ex.volume == 1500)
        ex.skipped = true
        #expect(ex.volume == 0)
        let burnout = WorkoutExercise(exerciseId: "b", exerciseName: "B", modality: .burnout, sets: 3, reps: 10, weight: 50)
        #expect(burnout.volume == 0)
    }

    @Test func encodesRequestsWithoutNilFields() throws {
        let encoder = RookJSON.makeEncoder()
        let cancel = String(decoding: try encoder.encode(UpdateWorkoutRequest.cancel), as: UTF8.self)
        #expect(cancel == #"{"status":"cancelled"}"#)

        let update = UserProfileUpdate(onboardingCompletedAt: ISO8601.parse("2026-03-01T00:00:00Z"))
        let json = String(decoding: try encoder.encode(update), as: UTF8.self)
        #expect(json == #"{"onboardingCompletedAt":"2026-03-01T00:00:00.000Z"}"#)
    }

    @Test func createWorkoutRequestDefaultsToFollowersOnly() throws {
        let request = CreateWorkoutRequest(exercises: [], source: .manual, gymId: "g", gymName: "Home")
        let object = try JSONSerialization.jsonObject(with: RookJSON.makeEncoder().encode(request)) as? [String: Any]
        #expect(object?["permissionType"] as? String == "FOLLOWERS_ONLY")
        #expect(object?["source"] as? String == "manual")
        #expect(object?["gymName"] as? String == "Home")
    }

    @Test func workoutExerciseRoundTrips() throws {
        let original = WorkoutExercise(
            exerciseId: "e", exerciseName: "E", modality: .setsReps, sets: 3, reps: 5,
            weight: 102.5, weightUnit: .kg, completedAt: ISO8601.parse("2026-03-14T18:00:00.250Z"),
            orderIndex: 1, lastPerformedDate: "2026-03-01"
        )
        let data = try RookJSON.makeEncoder().encode(original)
        let decoded = try RookJSON.makeDecoder().decode(WorkoutExercise.self, from: data)
        #expect(decoded == original)
    }

    @Test func weightUnitLabels() {
        #expect(WeightUnit.lbs.label == "lbs")
        #expect(WeightUnit.kg.label == "kg")
        #expect(WeightUnit(rawValue: "STONE").label == "lbs")
    }

    @Test func equipmentPresetsMatchWebApp() {
        #expect(EquipmentType.Preset.commercial.equipment.count == 6)
        #expect(EquipmentType.Preset.home.equipment.map(\.rawValue) == ["dumbbells", "free_weights", "cardio"])
        #expect(EquipmentType.Preset.minimalist.equipment == [.dumbbells])
        #expect(EquipmentType.freeWeights.label == "Free Weights")
    }

    @Test func iso8601ParsesBothForms() {
        #expect(ISO8601.parse("2026-03-14T18:02:11.123Z") != nil)
        #expect(ISO8601.parse("2026-03-14T18:02:11Z") != nil)
        #expect(ISO8601.parse("2026-03-14") == nil)
    }
}
