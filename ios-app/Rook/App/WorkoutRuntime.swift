import Foundation
import Observation
import RookFeatures

/// App-lifetime owner of the workout session controller. Created at launch (before any UI) because
/// Live Activity buttons can launch Rook in the background to run an intent.
@MainActor
@Observable
final class WorkoutRuntime {
    let controller: WorkoutSessionController
    private var restoreTask: Task<Void, Never>?

    init(controller: WorkoutSessionController) {
        self.controller = controller
        WorkoutIntentBridge.handler = { [weak self] action in
            await self?.handle(action)
        }
    }

    /// Restores a persisted workout exactly once per process.
    func ensureRestored() async {
        if restoreTask == nil {
            restoreTask = Task { await controller.restore() }
        }
        await restoreTask?.value
    }

    func handle(_ action: WorkoutIntentAction) async {
        await ensureRestored()
        switch action {
        case .pauseResume: await controller.togglePause()
        case .nextExercise: await controller.advanceFromLiveActivity()
        }
    }
}
