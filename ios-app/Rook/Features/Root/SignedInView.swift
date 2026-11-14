import RookFeatures
import RookModels
import SwiftUI

/// Navigation destinations inside the signed-in app.
enum AppRoute: Hashable {
    case profile
    case settings
    case history
    case workoutDetail(WorkoutInstance)
}

/// The signed-in app shell: dashboard at the root of a navigation stack, the builder and the
/// workout screen as full-screen covers.
struct SignedInView: View {
    let appModel: AppModel
    let dependencies: AppDependencies
    let controller: WorkoutSessionController
    let profile: UserProfile
    @State private var path: [AppRoute] = []
    @State private var dashboard: DashboardModel
    @State private var showingBuilder = false
    @State private var showingExecution = false
    @Environment(ToastCenter.self) private var toasts

    init(appModel: AppModel, dependencies: AppDependencies, controller: WorkoutSessionController, profile: UserProfile) {
        self.appModel = appModel
        self.dependencies = dependencies
        self.controller = controller
        self.profile = profile
        _dashboard = State(initialValue: DashboardModel(api: dependencies.api, unit: profile.preferredUnit) {
            await appModel.sessionExpired()
        })
    }

    var body: some View {
        NavigationStack(path: $path) {
            DashboardView(
                model: dashboard,
                profile: profile,
                activeWorkoutBanner: banner,
                onNewWorkout: newWorkout
            )
            .navigationDestination(for: AppRoute.self, destination: destination)
        }
        .onAppear {
            controller.unit = profile.preferredUnit
            // Resume straight into a workout restored from a previous launch.
            if controller.isActive { showingExecution = true }
        }
        .onChange(of: profile.preferredUnit) { _, unit in
            dashboard.unit = unit
            controller.unit = unit
        }
        .fullScreenCover(isPresented: $showingBuilder) {
            BuilderFlowView(
                model: BuilderModel(
                    api: dependencies.api, aiStream: dependencies.aiStream, unit: profile.preferredUnit
                ) { await appModel.sessionExpired() },
                makeHistory: { HistoryModel(api: dependencies.api) { await appModel.sessionExpired() } },
                onStarted: { workout in
                    await controller.begin(with: workout)
                    showingBuilder = false
                    showingExecution = true
                }
            )
        }
        .fullScreenCover(isPresented: $showingExecution) {
            ExecutionView(controller: controller) { completed in
                showingExecution = false
                if completed { toasts.show("Workout saved", kind: .success) }
                Task { await dashboard.load() }
            }
        }
    }

    private var banner: AnyView? {
        guard let session = controller.session else { return nil }
        return AnyView(ActiveWorkoutBanner(session: session, now: controller.now) { showingExecution = true })
    }

    private func newWorkout() {
        if controller.isActive {
            showingExecution = true
        } else {
            showingBuilder = true
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .profile:
            ProfileView(profile: profile)
        case .settings:
            SettingsView(
                model: SettingsModel(
                    profile: profile,
                    api: dependencies.api,
                    biometrics: dependencies.biometrics,
                    preferences: dependencies.preferences,
                    appVersion: AppDependencies.appVersion,
                    onProfileChanged: { appModel.profileDidChange($0) },
                    onSessionExpired: { await appModel.sessionExpired() },
                    onAccountDeleted: { await appModel.signOut(notice: AuthNotice.accountDeleted) }
                ),
                onSignOut: { await appModel.signOut() }
            )
        case .history:
            HistoryView(
                model: HistoryModel(api: dependencies.api) { await appModel.sessionExpired() },
                unit: profile.preferredUnit
            )
        case .workoutDetail(let workout):
            WorkoutDetailView(workout: workout, unit: profile.preferredUnit)
        }
    }
}
