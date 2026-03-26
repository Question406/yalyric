import XCTest
@testable import yalyricLib

final class ThemeTests: XCTestCase {

    // MARK: - Equality

    func testEqualityDefault() {
        let a = Theme()
        let b = Theme()
        XCTAssertEqual(a, b)
    }

    func testEqualityKaraokeFillEnabled() {
        var a = Theme()
        var b = Theme()
        a.karaokeFillEnabled = true
        XCTAssertNotEqual(a, b)
        b.karaokeFillEnabled = true
        XCTAssertEqual(a, b)
    }

    func testEqualityFillEdgeWidth() {
        var a = Theme()
        var b = Theme()
        a.fillEdgeWidth = 0.10
        XCTAssertNotEqual(a, b)
        b.fillEdgeWidth = 0.10
        XCTAssertEqual(a, b)
    }

    func testEqualityAllFieldsDiffer() {
        var a = Theme()
        a.fontName = "Menlo"
        a.currentLineFontSize = 30
        a.karaokeFillEnabled = true
        a.fillEdgeWidth = 0.15
        let b = Theme()
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Karaoke Fill Gradient Locations

    func testGradientLocationsAtZero() {
        let locs = Self.computeGradientLocations(progress: 0, edgeWidth: 0.06)
        XCTAssertEqual(locs[0], 0, accuracy: 0.001)
        XCTAssertEqual(locs[1], 0, accuracy: 0.001)
        XCTAssertEqual(locs[2], 0.06, accuracy: 0.001)
        XCTAssertEqual(locs[3], 1, accuracy: 0.001)
    }

    func testGradientLocationsAtHalf() {
        let locs = Self.computeGradientLocations(progress: 0.5, edgeWidth: 0.06)
        XCTAssertEqual(locs[0], 0, accuracy: 0.001)
        XCTAssertEqual(locs[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(locs[2], 0.56, accuracy: 0.001)
        XCTAssertEqual(locs[3], 1, accuracy: 0.001)
    }

    func testGradientLocationsAtOne() {
        let locs = Self.computeGradientLocations(progress: 1.0, edgeWidth: 0.06)
        XCTAssertEqual(locs[0], 0, accuracy: 0.001)
        XCTAssertEqual(locs[1], 1.0, accuracy: 0.001)
        XCTAssertEqual(locs[2], 1.06, accuracy: 0.001)
        XCTAssertEqual(locs[3], 1, accuracy: 0.001)
    }

    func testGradientLocationsWideEdge() {
        let locs = Self.computeGradientLocations(progress: 0.3, edgeWidth: 0.20)
        XCTAssertEqual(locs[0], 0, accuracy: 0.001)
        XCTAssertEqual(locs[1], 0.3, accuracy: 0.001)
        XCTAssertEqual(locs[2], 0.5, accuracy: 0.001)
        XCTAssertEqual(locs[3], 1, accuracy: 0.001)
    }

    func testGradientLocationsClamped() {
        // Progress should be clamped 0-1
        let locs = Self.computeGradientLocations(progress: -0.5, edgeWidth: 0.06)
        XCTAssertEqual(locs[1], 0, accuracy: 0.001)  // clamped to 0

        let locs2 = Self.computeGradientLocations(progress: 1.5, edgeWidth: 0.06)
        XCTAssertEqual(locs2[1], 1.0, accuracy: 0.001)  // clamped to 1
    }

    // MARK: - Helper

    /// Mirror of the gradient location logic in OverlayWindow.updateProgress
    private static func computeGradientLocations(progress: Double, edgeWidth: CGFloat) -> [Float] {
        let p = Float(max(0, min(1, progress)))
        let edge = Float(edgeWidth)
        return [0, p, p + edge, 1]
    }
}
