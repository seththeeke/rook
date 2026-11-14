import Foundation
import Observation
import RookModels
import RookNetworking

/// Sauna sessions are ordinary workouts with a single timed "Sauna" exercise (catalog id
/// `recovery-sauna`). There is no separate backend type; the app recognises them by their exercises.
public enum Sauna {
    public static let exerciseId = "recovery-sauna"
    public static let exerciseName = "Sauna"
    public static let defaultMinutes = 20
    public static let minuteRange = 1...180
    public static let presetMinutes = [10, 15, 20, 30]

    /// True for the catalog's Sauna exercise (matched by id, or by name for safety).
    public static func isSauna(_ exercise: WorkoutExercise) -> Bool {
        exercise.exerciseId == exerciseId
            || exercise.exerciseName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(exerciseName) == .orderedSame
    }

    /// True when every logged exercise in the workout is a sauna session.
    public static func isSaunaWorkout(_ workout: WorkoutInstance) -> Bool {
        let logged = workout.exercises.filter { !$0.skipped }
        return !logged.isEmpty && logged.allSatisfy(isSauna)
    }

    /// Minutes spent in the sauna, from the exercise durations (the server's `durationMinutes` is the time
    /// between creating and completing the workout, which is ~0 for a logged session).
    public static func minutes(in workout: WorkoutInstance) -> Int {
        let seconds = workout.exercises.filter { !$0.skipped && isSauna($0) }.compactMap(\.durationSeconds).reduce(0, +)
        return Int((Double(seconds) / 60).rounded())
    }

    /// The single exercise a sauna workout is made of.
    public static func exercise(minutes: Int) -> WorkoutExercise {
        WorkoutExercise(
            exerciseId: exerciseId, exerciseName: exerciseName, modality: .duration,
            sets: 1, durationSeconds: minutes * 60, orderIndex: 0
        )
    }
}

/// The "Sauna" builder screen: pick a number of minutes and log a completed sauna session.
///
/// Logging is two existing calls: create the workout, then complete it with the same exercise.
@MainActor
@Observable
public final class SaunaLogModel {
    public var minutes: Int = Sauna.defaultMinutes {
        didSet {
            let clamped = min(max(minutes, Sauna.minuteRange.lowerBound), Sauna.minuteRange.upperBound)
            if clamped != minutes { minutes = clamped }
        }
    }
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    private let api: RookAPI
    private let gym: Gym?
    private let onSessionExpired: @MainActor () async -> Void

    public init(api: RookAPI, gym: Gym?, onSessionExpired: @escaping @MainActor () async -> Void) {
        self.api = api
        self.gym = gym
        self.onSessionExpired = onSessionExpired
    }

    public var canLog: Bool { !isSaving && Sauna.minuteRange.contains(minutes) }

    /// Creates and completes the sauna workout. Returns the completed workout, or nil after setting
    /// `errorMessage`. If completing fails, the just-created workout is cancelled so no half-started
    /// session is left behind.
    public func log() async -> WorkoutInstance? {
        guard canLog else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let exercise = Sauna.exercise(minutes: minutes)
        let created: WorkoutInstance
        do {
            created = try await api.createWorkout(CreateWorkoutRequest(
                exercises: [exercise], source: .manual, gymId: gym?.gymId, gymName: gym?.name
            ))
        } catch {
            return await fail(error)
        }
        do {
            return try await api.updateWorkout(id: created.id, .complete([exercise]))
        } catch {
            _ = try? await api.updateWorkout(id: created.id, .cancel)
            return await fail(error)
        }
    }

    private func fail(_ error: Error) async -> WorkoutInstance? {
        if isSessionExpired(error) { await onSessionExpired(); return nil }
        errorMessage = "Couldn't log your sauna session. \(userMessage(for: error))"
        return nil
    }
}
