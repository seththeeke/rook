import Foundation
import RookAuth
import RookFeatures
import RookNetworking
import RookSession
import RookWidgetData
import WidgetKit

/// The production object graph, created once at launch and passed down to features.
/// Features depend on protocols (`AuthService`, `RookAPI`, `AIWorkoutStreaming`, …), so tests build
/// their own graphs from fakes.
struct AppDependencies {
    let configuration: AppConfiguration
    let auth: AuthService
    let api: RookAPI
    let aiStream: AIWorkoutStreaming
    let sessionStore: SessionStoring
    let biometrics: BiometricAuthenticating
    let preferences: AppPreferences
    let stepCounter: StepCounting
    let widgetSync: WidgetSync

    @MainActor
    static func live(configuration: AppConfiguration) -> AppDependencies {
        let auth = AmplifyAuthService(configuration: configuration)
        let sessionStore: SessionStoring
        do {
            sessionStore = try FileSessionStore.standard()
        } catch {
            // Application Support is always available on iOS; failing here means a broken install.
            fatalError("Could not create session storage: \(error)")
        }
        return AppDependencies(
            configuration: configuration,
            auth: auth,
            api: LiveRookAPI(client: APIClient(baseURL: configuration.apiBaseURL, tokenProvider: auth)),
            aiStream: AIWorkoutStreamClient(url: configuration.aiStreamURL, tokenProvider: auth),
            sessionStore: sessionStore,
            biometrics: LocalBiometrics(),
            preferences: UserDefaultsPreferences(),
            stepCounter: MotionStepCounter(),
            widgetSync: WidgetSync(store: .shared) { WidgetCenter.shared.reloadAllTimelines() }
        )
    }

    /// "1.0 (12)" for Settings.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
