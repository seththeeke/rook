import SwiftUI

// MARK: - Buttons

/// Full-width filled button. Default fill is the purple accent gradient; pass `tint` for a solid color
/// (e.g. destructive red).
struct RookPrimaryButtonStyle: ButtonStyle {
    var tint: Color?
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Theme.accentGradient))
                    .opacity(isEnabled ? 1 : 0.35)
            }
            .shadow(color: (tint ?? Theme.primary).opacity(isEnabled ? 0.35 : 0), radius: 12, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Full-width gunmetal button with a hairline border, for secondary actions.
struct RookSecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.textPrimary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.35))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.surfaceElevated.opacity(isEnabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == RookPrimaryButtonStyle {
    static var rookPrimary: RookPrimaryButtonStyle { .init() }
    /// Completion actions use the same purple accent as every primary action.
    static var rookSuccess: RookPrimaryButtonStyle { .init() }
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
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.border, lineWidth: 1))
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
                .foregroundStyle(Theme.textSecondary)
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
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 52)
            .foregroundStyle(Theme.textPrimary)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(error == nil ? Theme.border : Theme.danger, lineWidth: 1)
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
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.primaryLight)
                .frame(width: 56, height: 56)
                .background(Theme.primary.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryLight)
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
                .foregroundStyle(Theme.textSecondary)
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
    .preferredColorScheme(.dark)
}
