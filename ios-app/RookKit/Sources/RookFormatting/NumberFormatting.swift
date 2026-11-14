import Foundation
import RookModels

/// Display formatting for numbers shown in the app. All functions are pure and locale-stable
/// (POSIX digits) so the UI matches what tests assert.
public enum RookFormat {
    /// Compact volume: 950 → "950", 12_450 → "12.5K", 1_000 → "1K", 3_400_000 → "3.4M".
    public static func compactVolume(_ value: Double) -> String {
        let v = max(0, value)
        switch v {
        case 1_000_000...: return trimmed(v / 1_000_000, fractionDigits: 1) + "M"
        case 1_000...: return trimmed(v / 1_000, fractionDigits: 1) + "K"
        default: return trimmed(v, fractionDigits: 0)
        }
    }

    /// Weight without a trailing ".0": 225 → "225", 102.5 → "102.5", 102.25 → "102.25".
    public static func weight(_ value: Double) -> String {
        trimmed(value, fractionDigits: 2)
    }

    /// Weight with unit: "225 lbs", "102.5 kg".
    public static func weight(_ value: Double, unit: WeightUnit) -> String {
        "\(weight(value)) \(unit.label)"
    }

    /// Elapsed clock: 75 → "01:15", 3_725 → "1:02:05". Negative values clamp to zero.
    public static func clock(seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Parses user-entered weight, accepting "." or "," as the decimal separator.
    /// Returns nil for empty, negative, non-numeric, or absurd (> 2000) values.
    public static func parseWeight(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite, value >= 0, value <= 2000 else {
            return nil
        }
        return value
    }

    private static func trimmed(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
