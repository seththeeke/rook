import RookFeatures
import RookModels
import SwiftUI

@main
struct RookApp: App {
    @State private var dependencies: AppDependencies
    @State private var appModel: AppModel
    @State private var workout: WorkoutRuntime
    @State private var network = NetworkMonitor()
    @State private var toasts = ToastCenter()

    init() {
        let dependencies = AppDependencies.live(configuration: .fromMainBundle())
        let appModel = AppModel(
            auth: dependencies.auth,
            api: dependencies.api,
            biometrics: dependencies.biometrics,
            preferences: dependencies.preferences
        )
        let controller = WorkoutSessionController(
            api: dependencies.api,
            store: dependencies.sessionStore,
            liveActivity: LiveActivityController(),
            unit: .lbs
        ) { await appModel.sessionExpired() }
        // Signing out discards any local workout and ends its Live Activity.
        appModel.onSignedOut = {
            await controller.discardLocally()
            dependencies.widgetSync.clear()
        }

        _dependencies = State(initialValue: dependencies)
        _appModel = State(initialValue: appModel)
        _workout = State(initialValue: WorkoutRuntime(controller: controller))
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel, dependencies: dependencies, workout: workout)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !network.isOnline { OfflineBanner() }
                }
                .toasts(toasts)
                .environment(toasts)
                .tint(Theme.primary)
                .preferredColorScheme(.dark)
        }
    }
}
