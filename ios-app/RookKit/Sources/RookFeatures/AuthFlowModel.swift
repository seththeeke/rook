import Foundation
import Observation
import RookAuth

/// Sign in, sign up, email confirmation, and password reset.
@MainActor
@Observable
public final class AuthFlowModel {
    public enum Screen: Equatable, Sendable {
        case signIn, signUp, confirmSignUp, forgotPassword, resetPassword
    }

    public var screen: Screen = .signIn
    public var email = ""
    public var password = ""
    public var confirmPassword = ""
    public var code = ""

    public private(set) var isWorking = false
    public private(set) var errorMessage: String?
    public private(set) var infoMessage: String?
    /// Inline field errors appear only after the user tries to submit.
    public private(set) var showValidation = false

    private let auth: AuthService
    private let onSignedIn: @MainActor () async -> Void

    public init(auth: AuthService, notice: String? = nil, onSignedIn: @escaping @MainActor () async -> Void) {
        self.auth = auth
        self.infoMessage = notice
        self.onSignedIn = onSignedIn
    }

    // MARK: - Validation

    public var emailError: String? {
        guard showValidation, !CredentialRules.isValidEmail(email) else { return nil }
        return "Enter a valid email address."
    }

    public var unmetPasswordRequirements: [CredentialRules.PasswordRequirement] {
        CredentialRules.unmetRequirements(for: password)
    }

    public var confirmPasswordError: String? {
        guard showValidation || !confirmPassword.isEmpty, confirmPassword != password else { return nil }
        return "Passwords don't match."
    }

    public var codeError: String? {
        guard showValidation, !CredentialRules.isValidCode(code) else { return nil }
        return "Enter the 6-digit code from your email."
    }

    // MARK: - Navigation

    public func go(to screen: Screen) {
        self.screen = screen
        errorMessage = nil
        infoMessage = nil
        showValidation = false
        if screen == .signIn || screen == .signUp || screen == .forgotPassword {
            password = ""
            confirmPassword = ""
            code = ""
        }
    }

    // MARK: - Actions

    public func signIn() async {
        showValidation = true
        guard CredentialRules.isValidEmail(email), !password.isEmpty else { return }
        await run {
            switch try await auth.signIn(email: email, password: password) {
            case .signedIn:
                await onSignedIn()
            case .needsConfirmation:
                try? await auth.resendSignUpCode(email: email)
                moveTo(.confirmSignUp, info: "Confirm your email to finish signing in. We sent a new code to \(displayEmail).")
            }
        }
    }

    public func signUp() async {
        showValidation = true
        guard CredentialRules.isValidEmail(email),
              CredentialRules.isValidPassword(password),
              password == confirmPassword
        else { return }
        await run {
            try await auth.signUp(email: email, password: password)
            moveTo(.confirmSignUp, info: "We sent a 6-digit code to \(displayEmail).")
        }
    }

    public func confirmSignUp() async {
        showValidation = true
        guard CredentialRules.isValidCode(code) else { return }
        await run {
            try await auth.confirmSignUp(email: email, code: code)
            // We still hold the password from sign-up/sign-in, so finish signing in for the user.
            if !password.isEmpty, try await auth.signIn(email: email, password: password) == .signedIn {
                await onSignedIn()
            } else {
                moveTo(.signIn, info: "Email confirmed. Sign in to continue.")
            }
        }
    }

    public func resendCode() async {
        await run {
            try await auth.resendSignUpCode(email: email)
            infoMessage = "We sent a new code to \(displayEmail)."
        }
    }

    public func requestPasswordReset() async {
        showValidation = true
        guard CredentialRules.isValidEmail(email) else { return }
        await run {
            try await auth.resetPassword(email: email)
            moveTo(.resetPassword, info: "If an account exists for \(displayEmail), we sent it a reset code.")
        }
    }

    public func confirmPasswordReset() async {
        showValidation = true
        guard CredentialRules.isValidCode(code),
              CredentialRules.isValidPassword(password),
              password == confirmPassword
        else { return }
        await run {
            try await auth.confirmResetPassword(email: email, newPassword: password, code: code)
            moveTo(.signIn, info: "Password updated. Sign in with your new password.")
        }
    }

    // MARK: - Helpers

    private var displayEmail: String { CredentialRules.normalizedEmail(email) }

    private func moveTo(_ next: Screen, info: String) {
        screen = next
        showValidation = false
        code = ""
        if next == .signIn || next == .resetPassword {
            password = ""
            confirmPassword = ""
        }
        infoMessage = info
    }

    private func run(_ body: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await body()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
