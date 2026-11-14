import Foundation
import Testing
import RookAuth
@testable import RookFeatures

@MainActor
@Suite("Auth flow")
struct AuthFlowModelTests {
    let auth = FakeAuth()

    func makeModel(signedIn: Locked<Int> = Locked(0)) -> AuthFlowModel {
        AuthFlowModel(auth: auth) { signedIn.mutate { $0 += 1 } }
    }

    @Test func signInValidatesBeforeCallingCognito() async {
        let model = makeModel()
        model.email = "nope"
        await model.signIn()
        #expect(model.emailError != nil)
        #expect(auth.calls.get().isEmpty)
    }

    @Test func successfulSignIn() async {
        let signedIn = Locked(0)
        let model = makeModel(signedIn: signedIn)
        model.email = "Lee@Example.com"
        model.password = "Secret123"
        await model.signIn()
        #expect(signedIn.get() == 1)
        #expect(model.errorMessage == nil)
        #expect(!model.isWorking)
    }

    @Test func wrongPasswordShowsMessage() async {
        auth.signInResults = [.failure(AuthFailure.invalidCredentials)]
        let model = makeModel()
        model.email = "lee@example.com"
        model.password = "bad"
        await model.signIn()
        #expect(model.errorMessage == AuthFailure.invalidCredentials.userMessage)
    }

    @Test func unconfirmedSignInResendsCodeAndMovesToConfirm() async {
        auth.signInResults = [.success(.needsConfirmation)]
        let model = makeModel()
        model.email = "lee@example.com"
        model.password = "Secret123"
        await model.signIn()
        #expect(model.screen == .confirmSignUp)
        #expect(auth.calls.get().contains("resend"))
        #expect(model.infoMessage?.contains("lee@example.com") == true)
        #expect(model.password == "Secret123") // kept for auto sign-in after confirming
    }

    @Test func signUpRequiresStrongMatchingPassword() async {
        let model = makeModel()
        model.go(to: .signUp)
        model.email = "lee@example.com"
        model.password = "weak"
        model.confirmPassword = "weak"
        await model.signUp()
        #expect(auth.calls.get().isEmpty)
        #expect(!model.unmetPasswordRequirements.isEmpty)

        model.password = "Strong123"
        model.confirmPassword = "Strong124"
        await model.signUp()
        #expect(model.confirmPasswordError == "Passwords don't match.")
        #expect(auth.calls.get().isEmpty)

        model.confirmPassword = "Strong123"
        await model.signUp()
        #expect(model.screen == .confirmSignUp)
    }

    @Test func confirmingSignsInAutomatically() async {
        let signedIn = Locked(0)
        let model = makeModel(signedIn: signedIn)
        model.go(to: .signUp)
        model.email = "lee@example.com"
        model.password = "Strong123"
        model.confirmPassword = "Strong123"
        await model.signUp()
        model.code = "12345"
        await model.confirmSignUp()
        #expect(model.codeError != nil)
        model.code = "123456"
        await model.confirmSignUp()
        #expect(signedIn.get() == 1)
        #expect(auth.calls.get().suffix(2) == ["confirm:123456", "signIn:lee@example.com"])
    }

    @Test func confirmWithoutPasswordReturnsToSignIn() async {
        let model = makeModel()
        model.screen = .confirmSignUp
        model.email = "lee@example.com"
        model.code = "123456"
        await model.confirmSignUp()
        #expect(model.screen == .signIn)
        #expect(model.infoMessage?.contains("confirmed") == true)
    }

    @Test func badCodeKeepsUserOnConfirm() async {
        auth.failure = AuthFailure.invalidCode
        let model = makeModel()
        model.screen = .confirmSignUp
        model.email = "lee@example.com"
        model.code = "123456"
        await model.confirmSignUp()
        #expect(model.screen == .confirmSignUp)
        #expect(model.errorMessage == AuthFailure.invalidCode.userMessage)
    }

    @Test func resendCodeShowsConfirmation() async {
        let model = makeModel()
        model.email = "lee@example.com"
        await model.resendCode()
        #expect(model.infoMessage?.contains("new code") == true)
    }

    @Test func passwordResetFlow() async {
        let model = makeModel()
        model.go(to: .forgotPassword)
        model.email = "bad"
        await model.requestPasswordReset()
        #expect(auth.calls.get().isEmpty)
        model.email = "lee@example.com"
        await model.requestPasswordReset()
        #expect(model.screen == .resetPassword)

        model.code = "654321"
        model.password = "NewPass123"
        model.confirmPassword = "NewPass123"
        await model.confirmPasswordReset()
        #expect(model.screen == .signIn)
        #expect(model.password.isEmpty)
        #expect(auth.calls.get().last == "confirmReset:654321")
    }

    @Test func resetRejectsWeakPassword() async {
        let model = makeModel()
        model.screen = .resetPassword
        model.email = "lee@example.com"
        model.code = "654321"
        model.password = "short"
        model.confirmPassword = "short"
        await model.confirmPasswordReset()
        #expect(auth.calls.get().isEmpty)
    }

    @Test func navigationClearsMessagesAndSecrets() {
        let model = AuthFlowModel(auth: auth, notice: "Session expired") {}
        #expect(model.infoMessage == "Session expired")
        model.password = "x"
        model.go(to: .signUp)
        #expect(model.infoMessage == nil)
        #expect(model.password.isEmpty)
        #expect(model.emailError == nil)
    }
}
