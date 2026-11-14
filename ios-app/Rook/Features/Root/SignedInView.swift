import RookFeatures
import RookModels
import SwiftUI

/// Navigation destinations inside the signed-in app.
enum AppRoute: Hashable {
    case profile
    case settings
}

/// The signed-in app shell and its navigation stack.
struct SignedInView: View {
    let appModel: AppModel
    let dependencies: AppDependencies
    let profile: UserProfile
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ProfileView(profile: profile)
                .navigationDestination(for: AppRoute.self, destination: destination)
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
        }
    }
}
