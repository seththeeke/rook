import Amplify
import AWSCognitoAuthPlugin
import Foundation
import RookAuth
import os

/// Cognito authentication via Amplify Swift (Auth category only).
///
/// The user pool's app client only allows SRP sign-in (`authFlows: { userSrp: true }` in
/// `packages/cdk/lib/auth.ts`), which Amplify implements. Email/password sign-in needs no redirect URL,
/// so the new bundle ID requires no backend changes (spec D1).
final class AmplifyAuthService: AuthService, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.rookfitness.app", category: "auth")
    private static let configureLock = NSLock()
    nonisolated(unsafe) private static var isConfigured = false

    init(configuration: AppConfiguration) {
        Self.configureOnce(configuration)
    }

    /// Amplify must be configured exactly once per process.
    private static func configureOnce(_ configuration: AppConfiguration) {
        configureLock.lock()
        defer { configureLock.unlock() }
        guard !isConfigured else { return }
        do {
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.configure(AmplifyConfiguration(auth: authCategoryConfiguration(configuration)))
            isConfigured = true
        } catch {
            // Only possible with a malformed configuration, which AppConfiguration already validated.
            fatalError("Amplify configuration failed: \(error)")
        }
    }

    /// Classic `amplifyconfiguration.json` shape for the Cognito plugin, built in code.
    static func authCategoryConfiguration(_ configuration: AppConfiguration) -> AuthCategoryConfiguration {
        AuthCategoryConfiguration(plugins: [
            "awsCognitoAuthPlugin": .object([
                "CognitoUserPool": .object([
                    "Default": .object([
                        "PoolId": .string(configuration.cognitoUserPoolID),
                        "AppClientId": .string(configuration.cognitoClientID),
                        "Region": .string(configuration.cognitoRegion),
                    ]),
                ]),
                "Auth": .object([
                    "Default": .object([
                        "authenticationFlowType": .string("USER_SRP_AUTH"),
                    ]),
                ]),
            ]),
        ])
    }

    // MARK: - AuthService

    func hasSession() async -> Bool {
        do {
            return try await Amplify.Auth.fetchAuthSession().isSignedIn
        } catch {
            return false
        }
    }

    func idToken(forceRefresh: Bool) async throws -> String {
        let options = forceRefresh ? AuthFetchSessionRequest.Options.forceRefresh() : .init()
        let session = try await Amplify.Auth.fetchAuthSession(options: options)
        guard let cognito = session as? AWSAuthCognitoSession else { throw AuthFailure.unknown("No Cognito session") }
        switch cognito.getCognitoTokens() {
        case .success(let tokens): return tokens.idToken
        case .failure(let error): throw Self.map(error)
        }
    }

    func signIn(email: String, password: String) async throws -> SignInOutcome {
        do {
            // A stale session (e.g. after reinstall) makes Amplify reject a new sign-in; clear it first.
            if await hasSession() { await signOut() }
            let result = try await Amplify.Auth.signIn(
                username: CredentialRules.normalizedEmail(email),
                password: password
            )
            return try Self.outcome(for: result.nextStep)
        } catch let error as AuthError {
            let failure = Self.map(error)
            if failure == .userNotConfirmed { return .needsConfirmation }
            throw failure
        }
    }

    func signUp(email: String, password: String) async throws {
        let normalized = CredentialRules.normalizedEmail(email)
        do {
            _ = try await Amplify.Auth.signUp(
                username: normalized,
                password: password,
                options: .init(userAttributes: [AuthUserAttribute(.email, value: normalized)])
            )
        } catch let error as AuthError {
            throw Self.map(error)
        }
    }

    func confirmSignUp(email: String, code: String) async throws {
        do {
            _ = try await Amplify.Auth.confirmSignUp(
                for: CredentialRules.normalizedEmail(email),
                confirmationCode: code.trimmingCharacters(in: .whitespaces)
            )
        } catch let error as AuthError {
            throw Self.map(error)
        }
    }

    func resendSignUpCode(email: String) async throws {
        do {
            _ = try await Amplify.Auth.resendSignUpCode(for: CredentialRules.normalizedEmail(email))
        } catch let error as AuthError {
            throw Self.map(error)
        }
    }

    func resetPassword(email: String) async throws {
        do {
            _ = try await Amplify.Auth.resetPassword(for: CredentialRules.normalizedEmail(email))
        } catch let error as AuthError {
            throw Self.map(error)
        }
    }

    func confirmResetPassword(email: String, newPassword: String, code: String) async throws {
        do {
            try await Amplify.Auth.confirmResetPassword(
                for: CredentialRules.normalizedEmail(email),
                with: newPassword,
                confirmationCode: code.trimmingCharacters(in: .whitespaces)
            )
        } catch let error as AuthError {
            throw Self.map(error)
        }
    }

    func signOut() async {
        let result = await Amplify.Auth.signOut()
        if let cognito = result as? AWSCognitoSignOutResult, case .failed(let error) = cognito {
            Self.log.error("Sign-out failed: \(error.errorDescription, privacy: .public)")
        }
    }

    // MARK: - Mapping (internal for tests)

    static func outcome(for step: AuthSignInStep) throws -> SignInOutcome {
        switch step {
        case .done: return .signedIn
        case .confirmSignUp: return .needsConfirmation
        default: throw AuthFailure.unsupportedChallenge(String(describing: step))
        }
    }

    static func map(_ error: AuthError) -> AuthFailure {
        switch error {
        case .notAuthorized:
            return .invalidCredentials
        case .signedOut, .sessionExpired:
            return .invalidCredentials
        case .service(_, _, let underlying):
            guard let cognito = underlying as? AWSCognitoAuthError else {
                return .unknown(error.errorDescription)
            }
            return map(cognito, description: error.errorDescription)
        case .validation(_, let description, _, _):
            return .unknown(description)
        default:
            if isNetworkError(error) { return .network }
            return .unknown(error.errorDescription)
        }
    }

    static func map(_ cognito: AWSCognitoAuthError, description: String) -> AuthFailure {
        switch cognito {
        case .userNotFound: .invalidCredentials
        case .userNotConfirmed: .userNotConfirmed
        case .usernameExists, .aliasExists: .accountExists
        case .invalidPassword: .passwordRejected("")
        case .codeMismatch: .invalidCode
        case .codeExpired: .expiredCode
        case .limitExceeded, .requestLimitExceeded, .failedAttemptsLimitExceeded: .tooManyAttempts
        case .network: .network
        default: .unknown(description)
        }
    }

    private static func isNetworkError(_ error: AuthError) -> Bool {
        if case .service(_, _, let underlying) = error, underlying is URLError { return true }
        if case .unknown(_, let underlying) = error, underlying is URLError { return true }
        return false
    }
}
