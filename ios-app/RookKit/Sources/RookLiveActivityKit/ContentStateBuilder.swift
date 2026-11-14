import Foundation
import RookModels
import RookSession

/// Builds Live Activity content from the workout session (replaces `workoutLiveActivityPayload.ts`).
public enum ContentStateBuilder {
    public static func make(
        from session: WorkoutSessionState,
        unit: WeightUnit,
        now: Date
    ) -> WorkoutActivityAttributes.ContentState {
        let exercise = session.currentExercise
        let timed = exercise?.modality.isTimed ?? false
        let nextIndex = session.currentIndex + 1
        let next = session.exercises.indices.contains(nextIndex) ? session.exercises[nextIndex].exerciseName : nil
        let running = timed && session.isDurationRunning

        return WorkoutActivityAttributes.ContentState(
            workoutName: session.displayName,
            exerciseName: exercise?.exerciseName ?? "Workout",
            exercisePosition: min(session.currentIndex + 1, max(session.exercises.count, 1)),
            exerciseCount: max(session.exercises.count, 1),
            nextExerciseName: next,
            timerReference: session.timerReferenceDate,
            isPaused: session.isPaused,
            pausedElapsedSeconds: session.elapsedSeconds(at: now),
            modality: timed ? .duration : .setsReps,
            targetSets: timed ? nil : (exercise?.sets ?? WorkoutExercise.defaultSets),
            targetReps: timed ? nil : (exercise?.reps ?? WorkoutExercise.defaultReps),
            weight: timed ? nil : exercise?.weight,
            weightUnitLabel: timed ? nil : (exercise?.weightUnit ?? unit).label,
            durationTarget: timed ? session.currentDurationTarget : nil,
            durationEnd: running ? session.durationEndDate(at: now) : nil,
            durationRemaining: timed && !running ? session.durationRemainingSeconds(at: now) : nil
        )
    }
}
