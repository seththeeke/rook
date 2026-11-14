import Foundation
import RookNetworking

/// Result of a sign-in attempt.
public enum SignInOutcome: Equatable, Sendable {
    case signedIn
    /// The account exists but the email was never confirmed; send the user to the code screen.
    case needsConfirmation
}

/// Authentication failures, mapped from the identity provider into cases the UI can explain.
public enum AuthFailure: Error, Equatable, Sendable {
    case invalidCredentials
    case userNotConfirmed
    case accountExists
    case passwordRejected(String)
    case invalidCode
    case expiredCode
    case tooManyAttempts
    case network
    /// The pool asked for a step Rook doesn't support (e.g. MFA, forced password change).
    case unsupportedChallenge(String)
    case unknown(String)

    public var userMessage: String {
        switch self {
        case .invalidCredentials: "Incorrect email or password."
        case .userNotConfirmed: "Please confirm your email to finish creating your account."
        case .accountExists: "An account with this email already exists. Try signing in."
        case .passwordRejected(let reason):
            reason.isEmpty ? "That password doesn't meet the requirements." : reason
        case .invalidCode: "That code isn't right. Check the email we sent and try again."
        case .expiredCode: "That code has expired. Request a new one."
        case .tooManyAttempts: "Too many attempts. Please wait a few minutes and try again."
        case .network: "You're offline. Check your connection and try again."
        case .unsupportedChallenge:
            "This account needs an extra sign-in step that isn't supported in the app yet. Sign in on the web."
        case .unknown: "Something went wrong. Please try again."
        }
    }
}

/// Everything the app needs from the identity provider (Cognito). Feature code depends only on this
/// protocol; the Amplify-backed implementation lives in the app target, and tests use fakes.
public protocol AuthService: TokenProviding {
    /// True when a usable session exists (tokens present or refreshable).
    func hasSession() async -> Bool
    func signIn(email: String, password: String) async throws -> SignInOutcome
    /// Creates the account; Cognito then emails a confirmation code.
    func signUp(email: String, password: String) async throws
    func confirmSignUp(email: String, code: String) async throws
    func resendSignUpCode(email: String) async throws
    /// Emails a reset code.
    func resetPassword(email: String) async throws
    func confirmResetPassword(email: String, newPassword: String, code: String) async throws
    /// Clears local tokens. Never throws: a failed global sign-out still signs out locally.
    func signOut() async
}
