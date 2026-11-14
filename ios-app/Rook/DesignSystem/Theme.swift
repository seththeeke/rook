import SwiftUI
import UIKit

/// Rook's dark "gunmetal" design language: near-black canvas, layered gunmetal surfaces with hairline
/// borders, white text, and purple used as the accent (actions, selection, progress), not as a fill.
/// The app always renders in dark mode (`.preferredColorScheme(.dark)` at the root).
enum Theme {
    // MARK: Accent

    /// Purple accent for primary actions, selection, and progress.
    static let primary = Color(hex: 0x7C5CFA)
    static let primaryLight = Color(hex: 0x9F86FF)
    static let primaryDark = Color(hex: 0x5B3FD6)
    /// Gradient used on primary buttons and the accent icon tiles.
    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0x8B6CFF), Color(hex: 0x6A4BE8)], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: Semantic

    static let accentOrange = Color(hex: 0xFF8A3D)
    static let accentGreen = Color(hex: 0x34D399)
    static let danger = Color(hex: 0xF87171)
    static let warning = Color(hex: 0xFBBF24)

    // MARK: Surfaces

    /// App canvas. Identical to the logo's background (and `LaunchBackground`) so the wordmark and
    /// app icon blend in seamlessly.
    static let background = Color(hex: 0x111118)
    /// Cards and grouped rows (gunmetal).
    static let surface = Color(hex: 0x1B1B23)
    /// Raised controls inside cards (steppers, chips, round buttons).
    static let surfaceElevated = Color(hex: 0x26262F)
    /// Hairline border around cards and fields.
    static let border = Color.white.opacity(0.07)
    /// Workout execution screen background (same canvas, kept as its own token).
    static let executionBackground = background

    // MARK: Text

    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x9A9AA6)
    static let textTertiary = Color(hex: 0x5E5E69)

    /// Subtle top-of-screen glow behind headers (replaces the old solid purple header).
    static let headerGradient = LinearGradient(
        colors: [Color(hex: 0x1A1824), background], startPoint: .top, endPoint: .bottom
    )

    enum Radius {
        static let card: CGFloat = 18
        static let control: CGFloat = 14
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    /// Large numeric display (timers, stats) using the rounded SF variant.
    static func rookNumber(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension View {
    /// Gunmetal list styling: hides the system grouped background so rows sit on the Rook canvas.
    func rookListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }

    /// Row background for gunmetal lists and forms.
    func rookRow() -> some View {
        listRowBackground(Theme.surface)
    }
}
