import SwiftUI

/// A bare trendline: no axes or labels, scaled to its own min and max so small changes still show.
/// Green when the last value is above the first, neutral otherwise.
struct Sparkline: View {
    let values: [Double]
    var lineWidth: CGFloat = 1.5

    private var isUp: Bool { (values.last ?? 0) > (values.first ?? 0) }
    private var color: Color { isUp ? Theme.accentGreen : Theme.textTertiary }

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, in: geo.size, inset: lineWidth)
            if points.count >= 2 {
                Path { path in path.addLines(points) }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth * 2.4, height: lineWidth * 2.4)
                        .position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Values spread evenly across the width; a flat series sits on the midline.
    static func points(_ values: [Double], in size: CGSize, inset: CGFloat) -> [CGPoint] {
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return [] }
        let width = size.width - inset * 2
        let height = size.height - inset * 2
        let step = width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let fraction = high > low ? (value - low) / (high - low) : 0.5
            return CGPoint(x: inset + CGFloat(index) * step, y: inset + height * (1 - CGFloat(fraction)))
        }
    }
}
