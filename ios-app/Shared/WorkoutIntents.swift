import AppIntents
import Foundation

/// Actions the Live Activity / Dynamic Island buttons can trigger (Phase 4b).
enum WorkoutIntentAction: Sendable {
    case pauseResume
    case nextExercise
}

/// Connects Live Activity intents to the app's workout controller.
///
/// This file is compiled into both the app and the widget extension (the widget needs the intent types
/// to render buttons). `LiveActivityIntent.perform()` always runs in the **app** process, where Rook
/// installs `handler` at launch; in the widget process the handler is never set or called.
enum WorkoutIntentBridge {
    @MainActor static var handler: ((WorkoutIntentAction) async -> Void)?
}

struct PauseResumeWorkoutIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Workout"
    static let description = IntentDescription("Pauses or resumes the workout timer.")
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutIntentBridge.handler?(.pauseResume)
        return .result()
    }
}

struct NextExerciseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Exercise"
    static let description = IntentDescription("Moves the workout to the next exercise.")
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutIntentBridge.handler?(.nextExercise)
        return .result()
    }
}
