import Foundation
import Testing
import RookModels
@testable import RookSession

let t0 = Date(timeIntervalSince1970: 1_773_500_000)

func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

func makeSession(_ exercises: [WorkoutExercise]? = nil) -> WorkoutSessionState {
    WorkoutSessionState(
        workoutId: "w1",
        displayName: "My Gym",
        exercises: exercises ?? [
            WorkoutExercise(exerciseId: "bench", exerciseName: "Bench", modality: .setsReps, sets: 3, reps: 8, orderIndex: 0),
            WorkoutExercise(exerciseId: "plank", exerciseName: "Plank", modality: .duration, durationSeconds: 45, orderIndex: 1),
            WorkoutExercise(exerciseId: "row", exerciseName: "Row", modality: .setsReps, sets: 3, reps: 10, orderIndex: 2),
        ],
        startedAt: t0
    )
}

@Suite("Session elapsed time")
struct ElapsedTimeTests {
    @Test func elapsedFollowsWallClock() {
        let s = makeSession()
        #expect(s.elapsedSeconds(at: t0) == 0)
        #expect(s.elapsedSeconds(at: at(61.9)) == 61)
        #expect(s.elapsedSeconds(at: at(-5)) == 0) // clock skew never goes negative
    }

    @Test func pausedTimeIsExcluded() {
        var s = makeSession()
        s.pause(at: at(60))
        #expect(s.elapsedSeconds(at: at(90)) == 60) // frozen while paused
        s.resume(at: at(90))
        #expect(s.elapsedSeconds(at: at(120)) == 90)
        #expect(s.timerReferenceDate == at(30))
    }

    @Test func multiplePausesAccumulate() {
        var s = makeSession()
        s.pause(at: at(10)); s.resume(at: at(20))
        s.pause(at: at(30)); s.resume(at: at(45))
        #expect(s.elapsedSeconds(at: at(100)) == 75)
        #expect(s.pausedInterval(at: at(100)) == 25)
    }

    @Test func doublePauseAndDoubleResumeAreNoOps() {
        var s = makeSession()
        s.pause(at: at(10))
        s.pause(at: at(50))
        #expect(s.pauseStartedAt == at(10))
        s.resume(at: at(60))
        s.resume(at: at(70))
        #expect(s.elapsedSeconds(at: at(100)) == 50)
    }

    @Test func displayNameIsNormalized() {
        #expect(WorkoutSessionState(workoutId: "w", displayName: "  ", exercises: [], startedAt: t0).displayName == nil)
        #expect(WorkoutSessionState(workoutId: "w", displayName: " Home ", exercises: [], startedAt: t0).displayName == "Home")
    }

    @Test func initFromServerWorkoutUsesServerStartAndOrder() {
        let workout = WorkoutInstance(
            workoutInstanceId: "srv", status: .inProgress, startedAt: at(-300), gymName: "Garage",
            exercises: [
                WorkoutExercise(exerciseId: "b", exerciseName: "B", modality: .setsReps, orderIndex: 1),
                WorkoutExercise(exerciseId: "a", exerciseName: "A", modality: .setsReps, orderIndex: 0),
            ]
        )
        let s = WorkoutSessionState(workout: workout)
        #expect(s.workoutId == "srv")
        #expect(s.displayName == "Garage")
        #expect(s.exercises.map(\.exerciseId) == ["a", "b"])
        #expect(s.elapsedSeconds(at: t0) == 300)
    }
}

@Suite("Session navigation and logging")
struct NavigationTests {
    @Test func advanceAndGoBackRespectBounds() {
        var s = makeSession()
        #expect(s.isFirst)
        let backFromFirst = s.goBack()
        #expect(backFromFirst == false)
        let first = s.advance()
        let second = s.advance()
        #expect(first && second)
        #expect(s.isLast)
        let pastLast = s.advance()
        #expect(pastLast == false)
        #expect(s.currentExercise?.exerciseId == "row")
        s.goTo(99)
        #expect(s.currentIndex == 2)
        s.goTo(-4)
        #expect(s.currentIndex == 0)
    }

    @Test func emptySessionIsSafe() {
        var s = makeSession([])
        s.goTo(1)
        s.setWeight(10, unit: .lbs)
        s.skipCurrent()
        s.startDuration(at: t0)
        s.completeDuration(unit: .lbs)
        #expect(s.currentExercise == nil)
        #expect(s.canComplete == false)
    }

    @Test func setWeightUnskipsAndRecordsUnit() {
        var s = makeSession()
        s.skipCurrent()
        s.setWeight(102.5, unit: .kg)
        #expect(s.exercises[0].weight == 102.5)
        #expect(s.exercises[0].weightUnit == .kg)
        #expect(s.exercises[0].skipped == false)
    }

    @Test func completionRequiresEveryExerciseLoggedOrSkipped() {
        var s = makeSession()
        // The plank already has a duration target, which is all the server requires for timed work.
        #expect(s.completionBlockers == [0, 2])
        s.setWeight(135, unit: .lbs)
        s.advance()
        s.completeDuration(unit: .lbs)
        s.advance()
        #expect(s.completionBlockers == [2])
        #expect(!s.canComplete)
        s.skipCurrent()
        #expect(s.canComplete)
        #expect(s.skippedCount == 1)
    }
}

@Suite("Duration segments")
struct DurationTests {
    private func onPlank() -> WorkoutSessionState {
        var s = makeSession()
        s.advance()
        return s
    }

    @Test func countdownRunsPausesAndClamps() {
        var s = onPlank()
        #expect(s.durationElapsedSeconds(at: at(5)) == 0)
        s.startDuration(at: at(10))
        #expect(s.isDurationRunning)
        #expect(s.durationElapsedSeconds(at: at(20)) == 10)
        #expect(s.durationRemainingSeconds(at: at(20)) == 35)
        #expect(s.durationEndDate(at: at(20)) == at(55))
        s.pauseDuration(at: at(30))
        #expect(!s.isDurationRunning)
        #expect(s.durationEndDate(at: at(30)) == nil)
        #expect(s.durationElapsedSeconds(at: at(100)) == 20) // frozen
        s.startDuration(at: at(100))
        #expect(s.durationElapsedSeconds(at: at(110)) == 30)
        #expect(s.durationElapsedSeconds(at: at(500)) == 45) // clamped to target
        #expect(s.durationRemainingSeconds(at: at(500)) == 0)
    }

    @Test func startingTwiceKeepsOriginalAnchor() {
        var s = onPlank()
        s.startDuration(at: at(10))
        s.startDuration(at: at(15))
        #expect(s.durationElapsedSeconds(at: at(20)) == 10)
    }

    @Test func pausingWorkoutPausesTheCountdown() {
        var s = onPlank()
        s.startDuration(at: at(10))
        s.pause(at: at(25))
        #expect(s.durationElapsedSeconds(at: at(60)) == 15)
        #expect(!s.isDurationRunning)
    }

    @Test func startingCountdownResumesPausedWorkout() {
        var s = onPlank()
        s.pause(at: at(10))
        s.startDuration(at: at(40))
        #expect(!s.isPaused)
        #expect(s.elapsedSeconds(at: at(50)) == 20)
    }

    @Test func leavingExerciseDiscardsSegment() {
        var s = onPlank()
        s.startDuration(at: at(10))
        s.advance()
        s.goBack()
        #expect(s.durationSegment == nil)
        #expect(s.durationElapsedSeconds(at: at(30)) == 0)
    }

    @Test func segmentOnlyAppliesToItsExercise() {
        var s = onPlank()
        s.startDuration(at: at(10))
        s.goTo(0)
        #expect(!s.isDurationRunning)
        #expect(s.durationElapsedSeconds(at: at(20)) == 0)
        s.pauseDuration(at: at(20)) // no segment for this exercise: no-op
        #expect(s.durationSegment == nil)
    }

    @Test func completingDurationLogsZeroWeightAndClearsSegment() {
        var s = onPlank()
        s.startDuration(at: at(10))
        s.completeDuration(unit: .kg)
        #expect(s.exercises[1].weight == 0)
        #expect(s.exercises[1].weightUnit == .kg)
        #expect(s.exercises[1].durationSeconds == 45)
        #expect(s.durationSegment == nil)
    }

    @Test func missingDurationDefaultsToSixtySeconds() {
        var s = makeSession([WorkoutExercise(exerciseId: "x", exerciseName: "X", modality: .duration)])
        #expect(s.currentDurationTarget == 60)
        s.completeDuration(unit: .lbs)
        #expect(s.exercises[0].durationSeconds == 60)
    }

    @Test func skippingClearsSegment() {
        var s = onPlank()
        s.startDuration(at: at(10))
        s.skipCurrent()
        #expect(s.durationSegment == nil)
    }
}
