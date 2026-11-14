import Foundation
import Testing
import RookModels
import RookSession
@testable import RookLiveActivityKit

private let t0 = Date(timeIntervalSince1970: 1_773_500_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

private func session() -> WorkoutSessionState {
    WorkoutSessionState(
        workoutId: "w1",
        displayName: "Garage",
        exercises: [
            WorkoutExercise(exerciseId: "bench", exerciseName: "Bench Press", modality: .setsReps, sets: 4, reps: 6, orderIndex: 0),
            WorkoutExercise(exerciseId: "plank", exerciseName: "Plank", modality: .duration, durationSeconds: 45, orderIndex: 1),
        ],
        startedAt: t0
    )
}

@Suite("Live Activity content")
struct ContentStateBuilderTests {
    @Test func setsRepsExercise() {
        var s = session()
        s.setWeight(135, unit: .lbs)
        let state = ContentStateBuilder.make(from: s, unit: .kg, now: at(90))
        #expect(state.workoutName == "Garage")
        #expect(state.exerciseName == "Bench Press")
        #expect(state.progressDescription == "Exercise 1 of 2")
        #expect(state.nextExerciseName == "Plank")
        #expect(state.modality == .setsReps)
        #expect(state.targetDescription == "4 sets × 6 reps")
        #expect(state.weightDescription == "135 lbs") // the exercise's own unit wins
        #expect(state.timerReference == t0)
        #expect(!state.isPaused)
        #expect(state.elapsedSeconds(at: at(100)) == 100)
        #expect(state.durationEnd == nil && state.durationTarget == nil)
    }

    @Test func weightFallsBackToProfileUnitAndHidesBodyweight() {
        var s = session()
        var state = ContentStateBuilder.make(from: s, unit: .kg, now: t0)
        #expect(state.weightUnitLabel == "kg")
        #expect(state.weightDescription == nil) // nothing logged yet
        s.setWeight(0, unit: .kg)
        state = ContentStateBuilder.make(from: s, unit: .kg, now: t0)
        #expect(state.weightDescription == nil)
        s.setWeight(102.5, unit: .kg)
        state = ContentStateBuilder.make(from: s, unit: .kg, now: t0)
        #expect(state.weightDescription == "102.5 kg")
    }

    @Test func pausedSessionFreezesElapsedAndShiftsReference() {
        var s = session()
        s.pause(at: at(60))
        let paused = ContentStateBuilder.make(from: s, unit: .lbs, now: at(200))
        #expect(paused.isPaused)
        #expect(paused.pausedElapsedSeconds == 60)
        #expect(paused.elapsedSeconds(at: at(500)) == 60)
        s.resume(at: at(200))
        let resumed = ContentStateBuilder.make(from: s, unit: .lbs, now: at(200))
        #expect(resumed.timerReference == at(140)) // 140 s paused
        #expect(resumed.elapsedSeconds(at: at(260)) == 120)
    }

    @Test func runningDurationHasEndDate() {
        var s = session()
        s.advance()
        s.startDuration(at: at(100))
        let state = ContentStateBuilder.make(from: s, unit: .lbs, now: at(110))
        #expect(state.modality == .duration)
        #expect(state.targetDescription == "45 s")
        #expect(state.durationEnd == at(145))
        #expect(state.durationRemaining == nil)
        #expect(state.nextExerciseName == nil)
        #expect(state.targetSets == nil && state.weightDescription == nil)
    }

    @Test func pausedDurationShowsRemaining() {
        var s = session()
        s.advance()
        s.startDuration(at: at(100))
        s.pauseDuration(at: at(120))
        let state = ContentStateBuilder.make(from: s, unit: .lbs, now: at(300))
        #expect(state.durationEnd == nil)
        #expect(state.durationRemaining == 25)
    }

    @Test func emptySessionIsSafe() {
        let s = WorkoutSessionState(workoutId: "w", displayName: nil, exercises: [], startedAt: t0)
        let state = ContentStateBuilder.make(from: s, unit: .lbs, now: t0)
        #expect(state.exerciseName == "Workout")
        #expect(state.progressDescription == "Exercise 1 of 1")
        #expect(state.workoutName == nil)
    }

    @Test func contentStateRoundTripsThroughJSON() throws {
        let state = ContentStateBuilder.make(from: session(), unit: .lbs, now: t0)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: data) == state)
        #expect(WorkoutActivityAttributes(workoutId: "w1").workoutId == "w1")
    }
}
