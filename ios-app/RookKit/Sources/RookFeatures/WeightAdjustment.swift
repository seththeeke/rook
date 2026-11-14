import Foundation

/// Quick-adjust buttons under the weight field on the workout screen (−5, +5, +10, +25, +50).
/// Deltas are in the exercise's own unit, as in the web app.
public enum WeightAdjustment {
    public static let quickDeltas: [Double] = [-5, 5, 10, 25, 50]

    /// "−5", "+10".
    public static func label(for delta: Double) -> String {
        let magnitude = abs(delta).rounded() == abs(delta) ? String(Int(abs(delta))) : String(abs(delta))
        return (delta < 0 ? "\u{2212}" : "+") + magnitude
    }

    /// Applies `delta` to the current weight (empty or invalid counts as 0), never going below 0.
    public static func apply(_ delta: Double, to current: Double?) -> Double {
        max(0, (current ?? 0) + delta)
    }
}
