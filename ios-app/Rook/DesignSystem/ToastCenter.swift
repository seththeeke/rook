import Observation
import SwiftUI

/// App-wide transient messages ("Workout saved", "Couldn't update units"…).
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        enum Kind { case success, error, info }
        let id = UUID()
        let kind: Kind
        let message: String
    }

    private(set) var current: Toast?
    private let displayDuration: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var dismissTask: Task<Void, Never>?

    init(
        displayDuration: Duration = .seconds(3),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.displayDuration = displayDuration
        self.sleep = sleep
    }

    /// Shows a toast, replacing any visible one, and schedules its dismissal.
    func show(_ message: String, kind: Toast.Kind = .info) {
        let toast = Toast(kind: kind, message: message)
        current = toast
        dismissTask?.cancel()
        dismissTask = Task { [weak self, displayDuration, sleep] in
            try? await sleep(displayDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss(toast)
        }
    }

    func dismiss(_ toast: Toast? = nil) {
        guard toast == nil || toast == current else { return }
        current = nil
    }
}

/// Renders the current toast at the top of its container.
struct ToastOverlay: ViewModifier {
    let center: ToastCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = center.current {
                Label(toast.message, systemImage: icon(for: toast.kind))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s + 2)
                    .background(color(for: toast.kind), in: Capsule())
                    .shadow(radius: 8, y: 4)
                    .padding(.top, Theme.Spacing.s)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { center.dismiss(toast) }
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("toast")
            }
        }
        .animation(.spring(duration: 0.3), value: center.current)
    }

    private func icon(for kind: ToastCenter.Toast.Kind) -> String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func color(for kind: ToastCenter.Toast.Kind) -> Color {
        switch kind {
        case .success: Theme.accentGreen
        case .error: Theme.danger
        case .info: Theme.primaryDark
        }
    }
}

extension View {
    func toasts(_ center: ToastCenter) -> some View { modifier(ToastOverlay(center: center)) }
}
