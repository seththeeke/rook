import SwiftUI

// MARK: - Buttons

/// Full-width filled button. Use `.buttonStyle(.rookPrimary)`; pair with `isLoading` via `RookButton`.
struct RookPrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(isEnabled ? 1 : 0.45), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Full-width outlined button for secondary actions.
struct RookSecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.45))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(tint.opacity(isEnabled ? 0.6 : 0.25), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == RookPrimaryButtonStyle {
    static var rookPrimary: RookPrimaryButtonStyle { .init() }
    static var rookSuccess: RookPrimaryButtonStyle { .init(tint: Theme.accentGreen) }
    static var rookDestructive: RookPrimaryButtonStyle { .init(tint: Theme.danger) }
}

extension ButtonStyle where Self == RookSecondaryButtonStyle {
    static var rookSecondary: RookSecondaryButtonStyle { .init() }
}

/// A button that shows a spinner and disables itself while `isLoading`.
struct RookButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(.white) }
            }
        }
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "Loading" : "")
    }
}

// MARK: - Cards

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

extension View {
    /// Standard content card used throughout the app.
    func rookCard() -> some View { modifier(CardModifier()) }
}

// MARK: - Text fields

/// Labeled text field with inline validation message.
struct RookTextField: View {
    enum Kind { case plain, email, password, newPassword, code }

    let label: String
    @Binding var text: String
    var kind: Kind = .plain
    var error: String?
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack {
                field
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(submitLabel)
                    .onSubmit(onSubmit)
                if isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 50)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(error == nil ? Color.secondary.opacity(0.25) : Theme.danger, lineWidth: 1)
            )
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
                    .accessibilityLabel("Error: \(error)")
            }
        }
    }

    private var isSecure: Bool { kind == .password || kind == .newPassword }

    @ViewBuilder private var field: some View {
        if isSecure && !isRevealed {
            SecureField(label, text: $text)
        } else {
            TextField(label, text: $text)
        }
    }

    private var contentType: UITextContentType? {
        switch kind {
        case .plain: nil
        case .email: .username
        case .password: .password
        case .newPassword: .newPassword
        case .code: .oneTimeCode
        }
    }

    private var keyboard: UIKeyboardType {
        switch kind {
        case .email: .emailAddress
        case .code: .numberPad
        default: .default
        }
    }
}

// MARK: - States

/// Friendly empty state with an optional action.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 56, height: 56)
                .background(Theme.primary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.l)
    }
}

/// Error state with a retry action.
struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again", action: retry)
                .buttonStyle(.rookSecondary)
                .frame(maxWidth: 220)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("state.error")
    }
}

/// Shown at the top of the app while the device is offline.
struct OfflineBanner: View {
    var body: some View {
        Label("You're offline. Some features may not work.", systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.black.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.warning)
            .accessibilityIdentifier("banner.offline")
    }
}

#Preview("Components") {
    ScrollView {
        VStack(spacing: 20) {
            RookButton(title: "Start workout") {}.buttonStyle(.rookPrimary)
            RookButton(title: "Saving", isLoading: true) {}.buttonStyle(.rookPrimary)
            Button("Secondary") {}.buttonStyle(.rookSecondary)
            RookTextField(label: "Email", text: .constant("lifter@"), kind: .email, error: "Enter a valid email")
            RookTextField(label: "Password", text: .constant("secret"), kind: .password)
            EmptyStateView(systemImage: "dumbbell", title: "No workouts yet", actionTitle: "Start a workout") {}
                .rookCard()
            ErrorStateView(message: "Something went wrong.") {}
            OfflineBanner()
        }
        .padding()
    }
    .background(Theme.background)
}
