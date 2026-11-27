import Foundation
import Testing
@testable import RookModels

private let dateA = Date(timeIntervalSince1970: 1_773_500_000)

@Suite("API response decoding")
struct DecodingTests {
    @Test func decodesOnboardedProfile() throws {
        let profile = try Fixture.decode(UserProfile.self, from: "users-me")
        #expect(profile.username == "athlete")
        #expect(profile.resolvedDisplayName == "Alex Athlete")
        #expect(profile.preferredUnit == .kg)
        #expect(profile.defaultGymId == "gym-1")
        #expect(profile.needsOnboarding == false)
        #expect(profile.createdAt == ISO8601.parse("2026-02-28T10:00:00Z"))
    }

    @Test func newProfileNeedsOnboarding() throws {
        let profile = try Fixture.decode(UserProfile.self, from: "users-me-new")
        #expect(profile.needsOnboarding)
        #expect(profile.preferredUnit == .lbs)
    }

    @Test func blankDisplayNameFallsBackToUsername() {
        let profile = UserProfile(userId: "u", username: "lifter", displayName: "   ")
        #expect(profile.resolvedDisplayName == "lifter")
    }

    @Test func decodesGymsAndPicksDefault() throws {
        let response = try Fixture.decode(GymsListResponse.self, from: "gyms")
        #expect(response.gyms.count == 2)
        #expect(response.preferredGym?.gymId == "gym-2")
    }

    @Test func preferredGymFallsBackToFirstWhenDefaultMissing() {
        let response = GymsListResponse(
            gyms: [Gym(gymId: "a", name: "A", equipmentTypes: [])],
            defaultGymId: "deleted"
        )
        #expect(response.preferredGym?.gymId == "a")
        #expect(GymsListResponse(gyms: [], defaultGymId: nil).preferredGym == nil)
    }

    @Test func decodesCatalogIncludingUnknownModality() throws {
        let items = try Fixture.decode([ExerciseCatalogItem].self, from: "exercises")
        #expect(items.count == 3)
        #expect(items[0].modality == .setsReps)
        #expect(items[1].modality == .duration)
        #expect(items[2].modality.rawValue == "some_future_modality")
        #expect(items[2].muscleGroups == nil)
    }

    @Test func decodesInProgressWorkout() throws {
        let workout = try Fixture.decode(WorkoutInstance.self, from: "workout-in-progress")
        #expect(workout.status == .inProgress)
        #expect(workout.source == .aiGenerated)
        #expect(workout.startedAt == ISO8601.parse("2026-03-14T18:02:11.123Z"))
        #expect(workout.orderedExercises.map(\.exerciseId) == ["barbell-bench-press", "plank"])
        let bench = workout.orderedExercises[0]
        #expect(bench.lastUsedWeight == 185)
        #expect(bench.lastPerformedDate == "2026-03-10")
    }

    @Test func decodesWorkoutPageWithSparseItems() throws {
        let page = try Fixture.decode(WorkoutListPage.self, from: "workouts-page")
        #expect(page.items.count == 2)
        #expect(page.nextToken != nil)
        #expect(page.items[0].exercises[0].weight == 225.5)
        #expect(page.items[1].status == .cancelled)
        #expect(page.items[1].source == nil)
    }

    @Test func decodesMetrics() throws {
        let global = try Fixture.decode(GlobalMetrics.self, from: "metrics-global")
        #expect(global.totalWorkouts == 42)
        #expect(global.completedDates.last == "2026-03-14")
        let exercises = try Fixture.decode([ExerciseMetricsSummary].self, from: "metrics-exercises")
        #expect(exercises[1].maxWeightUnit == .kg)
        #expect(exercises[1].lastUsedWeight == nil)
        #expect(exercises[1].recentSessions.isEmpty)
        #expect(exercises[1].lastPerformedAt == nil)
        #expect(exercises[0].lastPerformedAt == ISO8601.parse("2026-03-13T23:40:12.345Z"))
        #expect(exercises[0].recentSessions.map(\.weight) == [215, 225.5])
        #expect(exercises[0].recentSessions[0].reps == 5)
        #expect(exercises[0].lastUsedWeightUnit == .lbs)
    }

    @Test func decodesExerciseSessions() throws {
        let json = #"{"exerciseId":"plank","sessions":[{"completedAt":"2026-03-14T15:00:00Z","workoutInstanceId":"w1","modality":"duration","sets":1,"durationSeconds":90},{"completedAt":"2026-03-15T15:00:00.000Z","weight":0}]}"#
        let response = try RookJSON.makeDecoder().decode(ExerciseSessionsResponse.self, from: Data(json.utf8))
        #expect(response.exerciseId == "plank")
        #expect(response.sessions[0].weight == 0) // missing weight decodes as 0
        #expect(response.sessions[0].modality == .duration)
        #expect(response.sessions[0].durationSeconds == 90)
        #expect(response.sessions[0].workoutInstanceId == "w1")
        #expect(response.sessions[1].id == ISO8601.parse("2026-03-15T15:00:00Z"))
        let recent = RecentSession(completedAt: dateA, weight: 10, weightUnit: .kg, reps: 8, durationSeconds: 30)
        let session = ExerciseSession(recent)
        #expect(session.weight == 10 && session.weightUnit == .kg && session.reps == 8 && session.durationSeconds == 30)
        let roundTrip = try RookJSON.makeDecoder().decode(ExerciseSessionsResponse.self, from: RookJSON.makeEncoder().encode(response))
        #expect(roundTrip == response)
    }

    @Test func metricsDecodeWithMissingFields() throws {
        let global = try RookJSON.makeDecoder().decode(GlobalMetrics.self, from: Data("{}".utf8))
        #expect(global == .empty)
    }

    @Test func decodesErrorBody() throws {
        let body = try Fixture.decode(APIErrorBody.self, from: "error")
        #expect(body.error.contains("Cannot modify"))
    }

    @Test func rejectsUnparseableDates() {
        let json = Data(#"{"workoutInstanceId":"x","status":"completed","startedAt":"yesterday"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try RookJSON.makeDecoder().decode(WorkoutInstance.self, from: json)
        }
    }
}
