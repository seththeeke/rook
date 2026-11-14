import Foundation
import RookWidgetData

/// Keeps the home-screen widgets' snapshot current.
///
/// Every new snapshot is written (so the widgets' fallback step count stays fresh), but widget timelines
/// are only reloaded when the dashboard figures change, not on every step.
@MainActor
public final class WidgetSync {
    private let store: DashboardSnapshotStore
    private let reload: @MainActor () -> Void
    private var lastContent: DashboardSnapshot?

    public init(store: DashboardSnapshotStore, reload: @escaping @MainActor () -> Void) {
        self.store = store
        self.reload = reload
    }

    public func update(_ snapshot: DashboardSnapshot?) {
        guard let snapshot else { return }
        store.save(snapshot)
        if snapshot.content != lastContent {
            lastContent = snapshot.content
            reload()
        }
    }

    /// On sign-out: remove the data so the widgets don't keep showing the previous account.
    public func clear() {
        store.clear()
        lastContent = nil
        reload()
    }
}
