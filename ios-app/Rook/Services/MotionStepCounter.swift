@preconcurrency import CoreMotion
import RookFeatures

/// Step counts from the device pedometer (CoreMotion). Reading needs Motion & Fitness access; the first
/// query shows the system prompt (`NSMotionUsageDescription`).
final class MotionStepCounter: StepCounting, @unchecked Sendable {
    // CMPedometer is thread-safe; one instance answers queries, each live stream gets its own.
    private let pedometer = CMPedometer()

    var access: StepAccess {
        guard CMPedometer.isStepCountingAvailable() else { return .unavailable }
        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted: return .denied
        default: return .available
        }
    }

    func steps(from start: Date, to end: Date) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data?.numberOfSteps.intValue ?? 0)
                }
            }
        }
    }

    func stepUpdates(from start: Date) -> AsyncStream<Int> {
        AsyncStream { continuation in
            let live = CMPedometer()
            live.startUpdates(from: start) { data, error in
                if error != nil {
                    continuation.finish()
                } else if let steps = data?.numberOfSteps.intValue {
                    continuation.yield(steps)
                }
            }
            continuation.onTermination = { _ in live.stopUpdates() }
        }
    }
}
