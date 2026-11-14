import Testing
@testable import RookFeatures

@Suite("Weight quick adjust")
struct WeightAdjustmentTests {
    @Test func offersTheRequiredButtonsInOrder() {
        #expect(WeightAdjustment.quickDeltas == [-5, 5, 10, 25, 50])
        #expect(WeightAdjustment.quickDeltas.map(WeightAdjustment.label) == ["\u{2212}5", "+5", "+10", "+25", "+50"])
    }

    @Test(arguments: [
        (Double?.some(135), 50.0, 185.0),
        (135, 25, 160),
        (135, -5, 130),
        (102.5, 10, 112.5),
        (nil, 25, 25),
        (3, -5, 0),
        (0, -5, 0),
    ])
    func appliesDeltaWithZeroFloor(current: Double?, delta: Double, expected: Double) {
        #expect(WeightAdjustment.apply(delta, to: current) == expected)
    }

    @Test func labelsFractionalDeltas() {
        #expect(WeightAdjustment.label(for: 2.5) == "+2.5")
    }
}
