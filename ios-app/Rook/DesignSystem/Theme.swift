import SwiftUI
import UIKit

/// Brand color tokens (unchanged from the web app's Tailwind theme), with dark-mode variants.
enum Theme {
    static let primary = Color(light: 0x7C3AED, dark: 0x8B5CF6)
    static let primaryLight = Color(hex: 0x8B5CF6)
    static let primaryDark = Color(hex: 0x6D28D9)
    static let accentOrange = Color(hex: 0xF97316)
    static let accentGreen = Color(hex: 0x22C55E)
    static let danger = Color(light: 0xDC2626, dark: 0xF87171)
    static let warning = Color(hex: 0xF59E0B)

    /// App background behind cards.
    static let background = Color(light: 0xF8F7FF, dark: 0x0F0F1A)
    /// Card / grouped surface.
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1B29)
    /// Always-dark background of the workout execution screen.
    static let executionBackground = Color(hex: 0x0F0F1A)

    static let headerGradient = LinearGradient(
        colors: [primary, primaryDark], startPoint: .top, endPoint: .bottom
    )

    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 12
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

    /// A color that adapts to light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

extension Font {
    /// Large numeric display (timers, stats) using the rounded SF variant.
    static func rookNumber(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
