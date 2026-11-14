import Foundation
import RookAuth
import RookNetworking
import RookSession

/// The production object graph, created once at launch and passed down to features.
/// Features depend on the protocols (`AuthService`, `AIWorkoutStreaming`, `SessionStoring`), so tests
/// construct their own graphs from fakes.
struct AppDependencies {
    let configuration: AppConfiguration
    let auth: AuthService
    let api: APIClient
    let aiStream: AIWorkoutStreaming
    let sessionStore: SessionStoring

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
            api: APIClient(baseURL: configuration.apiBaseURL, tokenProvider: auth),
            aiStream: AIWorkoutStreamClient(url: configuration.aiStreamURL, tokenProvider: auth),
            sessionStore: sessionStore
        )
    }
}
