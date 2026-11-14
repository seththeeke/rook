import Network
import Observation

/// Publishes whether the device currently has a usable network path (drives the offline banner).
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "com.rookfitness.app.network-monitor"))
    }

    deinit {
        monitor.cancel()
    }
}
