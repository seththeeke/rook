import RookFeatures
import SwiftUI

@main
struct RookApp: App {
    @State private var dependencies: AppDependencies
    @State private var appModel: AppModel
    @State private var network = NetworkMonitor()
    @State private var toasts = ToastCenter()

    init() {
        let dependencies = AppDependencies.live(configuration: .fromMainBundle())
        _dependencies = State(initialValue: dependencies)
        _appModel = State(initialValue: AppModel(
            auth: dependencies.auth,
            api: dependencies.api,
            biometrics: dependencies.biometrics,
            preferences: dependencies.preferences
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel, dependencies: dependencies)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !network.isOnline { OfflineBanner() }
                }
                .toasts(toasts)
                .environment(toasts)
                .tint(Theme.primary)
        }
    }
}
