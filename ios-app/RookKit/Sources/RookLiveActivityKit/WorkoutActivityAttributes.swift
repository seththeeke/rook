import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Live Activity / Dynamic Island payload for an in-progress workout. Shared by the app (which starts and
/// updates the activity) and the widget extension (which renders it).
///
/// Ported from the Capacitor plugin's `WorkoutActivityAttributes`, with typed fields and `Date`s instead
/// of ISO strings. Timers are **date-anchored** (`Text(timerInterval:)` / `.timer`), so they keep ticking
/// on the Lock Screen without the app sending updates.
public struct WorkoutActivityAttributes: Codable, Hashable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Modality: String, Codable, Hashable, Sendable {
            case setsReps, duration
        }

        /// Gym or workout name shown above the exercise (nil = generic label).
        public var workoutName: String?
        public var exerciseName: String
        /// 1-based position, e.g. 2 of 6.
        public var exercisePosition: Int
        public var exerciseCount: Int
        public var nextExerciseName: String?

        /// While running, the elapsed timer reads `now - timerReference`.
        public var timerReference: Date
        public var isPaused: Bool
        /// Elapsed seconds frozen at the moment of pausing (shown while paused).
        public var pausedElapsedSeconds: Int

        public var modality: Modality
        public var targetSets: Int?
        public var targetReps: Int?
        public var weight: Double?
        /// "lbs" / "kg".
        public var weightUnitLabel: String?

        public var durationTarget: Int?
        /// Set while a duration countdown is running: when it reaches zero.
        public var durationEnd: Date?
        /// Seconds left when the countdown isn't running.
        public var durationRemaining: Int?

        public init(
            workoutName: String?,
            exerciseName: String,
            exercisePosition: Int,
            exerciseCount: Int,
            nextExerciseName: String?,
            timerReference: Date,
            isPaused: Bool,
            pausedElapsedSeconds: Int,
            modality: Modality,
            targetSets: Int?,
            targetReps: Int?,
            weight: Double?,
            weightUnitLabel: String?,
            durationTarget: Int?,
            durationEnd: Date?,
            durationRemaining: Int?
        ) {
            self.workoutName = workoutName
            self.exerciseName = exerciseName
            self.exercisePosition = exercisePosition
            self.exerciseCount = exerciseCount
            self.nextExerciseName = nextExerciseName
            self.timerReference = timerReference
            self.isPaused = isPaused
            self.pausedElapsedSeconds = pausedElapsedSeconds
            self.modality = modality
            self.targetSets = targetSets
            self.targetReps = targetReps
            self.weight = weight
            self.weightUnitLabel = weightUnitLabel
            self.durationTarget = durationTarget
            self.durationEnd = durationEnd
            self.durationRemaining = durationRemaining
        }

        /// "3 sets × 8 reps", "45 s".
        public var targetDescription: String {
            switch modality {
            case .setsReps: "\(targetSets ?? 3) sets × \(targetReps ?? 8) reps"
            case .duration: "\(durationTarget ?? 60) s"
            }
        }

        /// "135 lbs" when a weight is logged for the current exercise (bodyweight shows nothing).
        public var weightDescription: String? {
            guard let weight, weight > 0, let weightUnitLabel else { return nil }
            let number = weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
            return "\(number) \(weightUnitLabel)"
        }

        /// "Exercise 2 of 6".
        public var progressDescription: String { "Exercise \(exercisePosition) of \(exerciseCount)" }

        /// Elapsed seconds at `date` (for static rendering while paused or in previews).
        public func elapsedSeconds(at date: Date) -> Int {
            isPaused ? pausedElapsedSeconds : max(0, Int(date.timeIntervalSince(timerReference)))
        }
    }

    public var workoutId: String

    public init(workoutId: String) {
        self.workoutId = workoutId
    }
}

#if canImport(ActivityKit)
extension WorkoutActivityAttributes: ActivityAttributes {}
#endif
