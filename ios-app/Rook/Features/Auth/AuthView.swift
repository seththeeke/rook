import RookAuth
import RookFeatures
import SwiftUI

/// Sign in / sign up / confirm / forgot / reset, driven by `AuthFlowModel`.
struct AuthView: View {
    @State private var model: AuthFlowModel
    @FocusState private var focus: Field?

    enum Field { case email, password, confirm, code }

    init(model: AuthFlowModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header
                if let info = model.infoMessage {
                    banner(info, systemImage: "info.circle.fill", tint: Theme.primary)
                }
                if let error = model.errorMessage {
                    banner(error, systemImage: "exclamationmark.circle.fill", tint: Theme.danger)
                        .accessibilityIdentifier("auth.error")
                }
                form
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: model.screen)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityIdentifier("auth.title")
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.l)
    }

    private var title: String {
        switch model.screen {
        case .signIn: "Welcome to Rook"
        case .signUp: "Create your account"
        case .confirmSignUp: "Check your email"
        case .forgotPassword: "Reset password"
        case .resetPassword: "Choose a new password"
        }
    }

    private var subtitle: String {
        switch model.screen {
        case .signIn: "Sign in to build and track your workouts."
        case .signUp: "Start building and tracking your workouts."
        case .confirmSignUp: "Enter the 6-digit code we sent you."
        case .forgotPassword: "We'll email you a code to reset it."
        case .resetPassword: "Enter the code from your email and a new password."
        }
    }

    // MARK: - Forms

    @ViewBuilder
    private var form: some View {
        switch model.screen {
        case .signIn: signInForm
        case .signUp: signUpForm
        case .confirmSignUp: confirmForm
        case .forgotPassword: forgotForm
        case .resetPassword: resetForm
        }
    }

    private var signInForm: some View {
        VStack(spacing: Theme.Spacing.m) {
            emailField(submit: .next) { focus = .password }
            RookTextField(label: "Password", text: $model.password, kind: .password, submitLabel: .go) {
                Task { await model.signIn() }
            }
            .focused($focus, equals: .password)
            .accessibilityIdentifier("auth.password")

            HStack {
                Spacer()
                Button("Forgot password?") { model.go(to: .forgotPassword) }
                    .font(.subheadline.weight(.medium))
            }
            RookButton(title: "Sign In", isLoading: model.isWorking) { Task { await model.signIn() } }
                .buttonStyle(.rookPrimary)
                .accessibilityIdentifier("auth.submit")
            switchPrompt("New to Rook?", action: "Create an account") { model.go(to: .signUp) }
        }
    }

    private var signUpForm: some View {
        VStack(spacing: Theme.Spacing.m) {
            emailField(submit: .next) { focus = .password }
            RookTextField(label: "Password", text: $model.password, kind: .newPassword) { focus = .confirm }
                .focused($focus, equals: .password)
            PasswordRequirementsView(password: model.password)
            RookTextField(
                label: "Confirm password", text: $model.confirmPassword, kind: .newPassword,
                error: model.confirmPasswordError, submitLabel: .go
            ) { Task { await model.signUp() } }
                .focused($focus, equals: .confirm)
            RookButton(title: "Create Account", isLoading: model.isWorking) { Task { await model.signUp() } }
                .buttonStyle(.rookPrimary)
            switchPrompt("Already have an account?", action: "Sign in") { model.go(to: .signIn) }
        }
    }

    private var confirmForm: some View {
        VStack(spacing: Theme.Spacing.m) {
            codeField { Task { await model.confirmSignUp() } }
            RookButton(title: "Confirm", isLoading: model.isWorking) { Task { await model.confirmSignUp() } }
                .buttonStyle(.rookPrimary)
            Button("Send a new code") { Task { await model.resendCode() } }
                .font(.subheadline.weight(.medium))
                .disabled(model.isWorking)
            switchPrompt("Wrong email?", action: "Start over") { model.go(to: .signUp) }
        }
        .onAppear { focus = .code }
    }

    private var forgotForm: some View {
        VStack(spacing: Theme.Spacing.m) {
            emailField(submit: .send) { Task { await model.requestPasswordReset() } }
            RookButton(title: "Send Reset Code", isLoading: model.isWorking) {
                Task { await model.requestPasswordReset() }
            }
            .buttonStyle(.rookPrimary)
            switchPrompt("Remembered it?", action: "Back to sign in") { model.go(to: .signIn) }
        }
    }

    private var resetForm: some View {
        VStack(spacing: Theme.Spacing.m) {
            codeField { focus = .password }
            RookTextField(label: "New password", text: $model.password, kind: .newPassword) { focus = .confirm }
                .focused($focus, equals: .password)
            PasswordRequirementsView(password: model.password)
            RookTextField(
                label: "Confirm new password", text: $model.confirmPassword, kind: .newPassword,
                error: model.confirmPasswordError, submitLabel: .go
            ) { Task { await model.confirmPasswordReset() } }
                .focused($focus, equals: .confirm)
            RookButton(title: "Update Password", isLoading: model.isWorking) {
                Task { await model.confirmPasswordReset() }
            }
            .buttonStyle(.rookPrimary)
            switchPrompt("Didn't get a code?", action: "Send again") { Task { await model.requestPasswordReset() } }
        }
    }

    // MARK: - Pieces

    private func emailField(submit: SubmitLabel, onSubmit: @escaping () -> Void) -> some View {
        RookTextField(label: "Email", text: $model.email, kind: .email, error: model.emailError, submitLabel: submit, onSubmit: onSubmit)
            .focused($focus, equals: .email)
            .accessibilityIdentifier("auth.email")
    }

    private func codeField(onSubmit: @escaping () -> Void) -> some View {
        RookTextField(label: "Verification code", text: $model.code, kind: .code, error: model.codeError, submitLabel: .done, onSubmit: onSubmit)
            .focused($focus, equals: .code)
    }

    private func switchPrompt(_ prompt: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(prompt).foregroundStyle(.secondary)
            Button(action, action: perform).fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.top, Theme.Spacing.s)
    }

    private func banner(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}

/// Live checklist of the Cognito password policy.
struct PasswordRequirementsView: View {
    let password: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(CredentialRules.PasswordRequirement.allCases, id: \.self) { requirement in
                let met = requirement.isMet(by: password)
                Label(requirement.label, systemImage: met ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                    .foregroundStyle(met ? Theme.accentGreen : .secondary)
                    .accessibilityLabel("\(requirement.label), \(met ? "met" : "not met")")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
