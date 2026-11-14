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

/// The signed-in app shell: dashboard at the root of a navigation stack.
struct SignedInView: View {
    let appModel: AppModel
    let dependencies: AppDependencies
    let profile: UserProfile
    @State private var path: [AppRoute] = []
    @State private var dashboard: DashboardModel

    init(appModel: AppModel, dependencies: AppDependencies, profile: UserProfile) {
        self.appModel = appModel
        self.dependencies = dependencies
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
                makeCalendar: {
                    CalendarModel(
                        api: dependencies.api,
                        completedDates: dashboard.global.completedDates,
                        knownWorkouts: dashboard.completedWorkouts
                    )
                }
            )
            .navigationDestination(for: AppRoute.self, destination: destination)
        }
        .onChange(of: profile.preferredUnit) { _, unit in dashboard.unit = unit }
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
