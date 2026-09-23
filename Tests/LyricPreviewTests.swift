import XCTest
import AppKit
@testable import yalyricLib

/// The Appearance tab's preview stays still for style edits and only animates
/// when the setting being changed is itself about motion. These cover the
/// decision function that splits those two cases, plus the sample rotation and
/// the karaoke gradient stops the stage draws.
final class LyricPreviewTests: XCTestCase {

    // MARK: - Demo triggers

    func testTransitionStyleChangeTriggersDemo() {
        var new = Theme()
        new.transitionStyle = .push
        XCTAssertTrue(LyricPreviewTrigger.needsDemo(from: Theme(), to: new))
    }

    func testAnimationDurationChangeTriggersDemo() {
        var new = Theme()
        new.animationDuration = 0.9
        XCTAssertTrue(LyricPreviewTrigger.needsDemo(from: Theme(), to: new))
    }

    func testKaraokeToggleTriggersDemo() {
        var new = Theme()
        new.karaokeFillEnabled = true
        XCTAssertTrue(LyricPreviewTrigger.needsDemo(from: Theme(), to: new))
    }

    func testFillEdgeWidthChangeTriggersDemo() {
        var old = Theme()
        old.karaokeFillEnabled = true
        var new = old
        new.fillEdgeWidth = 0.18
        XCTAssertTrue(LyricPreviewTrigger.needsDemo(from: old, to: new))
    }

    // MARK: - Style edits stay still

    func testFontSizeChangeDoesNotTriggerDemo() {
        var new = Theme()
        new.currentLineFontSize = 40
        XCTAssertFalse(LyricPreviewTrigger.needsDemo(from: Theme(), to: new))
    }

    func testColorAndBackgroundChangesDoNotTriggerDemo() {
        var new = Theme()
        new.textColor = .systemPink
        new.backgroundStyle = .solidPill
        new.backgroundCornerRadius = 20
        new.letterSpacing = 3
        new.shadowBlurRadius = 15
        new.nextLineOpacity = 0.9
        XCTAssertFalse(LyricPreviewTrigger.needsDemo(from: Theme(), to: new))
    }

    func testIdenticalThemeDoesNotTriggerDemo() {
        XCTAssertFalse(LyricPreviewTrigger.needsDemo(from: Theme(), to: Theme()))
    }

    // MARK: - Nothing to animate

    /// With no transition and no fill there is no motion to show, so the demo
    /// would only flicker the text. Selecting "None" settles the stage instead.
    func testNoTransitionAndNoFillHasNothingToDemo() {
        var old = Theme()
        old.transitionStyle = .slideUp
        var new = old
        new.transitionStyle = .none
        new.karaokeFillEnabled = false
        XCTAssertFalse(LyricPreviewTrigger.needsDemo(from: old, to: new))
    }

    func testKaraokeFillAloneIsEnoughToDemo() {
        var old = Theme()
        old.transitionStyle = .none
        var new = old
        new.karaokeFillEnabled = true
        XCTAssertTrue(LyricPreviewTrigger.needsDemo(from: old, to: new),
                      "the fill sweeps even when lines change instantly")
    }

    // MARK: - Sample lines

    func testSampleLinesAreDistinctAndNonEmpty() {
        let lines = LyricPreviewSample.lines
        XCTAssertGreaterThanOrEqual(lines.count, 3)
        XCTAssertFalse(lines.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        XCTAssertEqual(Set(lines).count, lines.count)
    }

    /// Han glyphs have very different metrics from Latin ones, so the stage has
    /// to show at least one CJK line or the font sliders lie for half the users.
    func testSampleLinesIncludeCJKAndLatin() {
        let lines = LyricPreviewSample.lines
        let han = CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}")
        XCTAssertTrue(lines.contains { $0.unicodeScalars.contains { han.contains($0) } })
        XCTAssertTrue(lines.contains { $0.unicodeScalars.allSatisfy { $0.isASCII } })
    }

    func testRotationWrapsAndNeverRepeatsAdjacentLines() {
        let count = LyricPreviewSample.lines.count
        var index = 0
        for _ in 0..<(count * 2) {
            let next = LyricPreviewSample.advance(index)
            XCTAssertNotEqual(LyricPreviewSample.line(at: next), LyricPreviewSample.line(at: index))
            index = next
        }
        XCTAssertEqual(LyricPreviewSample.advance(count - 1), 0)
    }

    func testLineIndexIsClampedIntoRange() {
        XCTAssertEqual(LyricPreviewSample.line(at: 0), LyricPreviewSample.lines[0])
        XCTAssertEqual(LyricPreviewSample.line(at: LyricPreviewSample.lines.count), LyricPreviewSample.lines[0])
        XCTAssertEqual(LyricPreviewSample.line(at: -1), LyricPreviewSample.lines[0])
    }

    // MARK: - Karaoke gradient stops

    func testFillLocationsAreMonotonicAndBounded() {
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            for edge in [0.02, 0.06, 0.20] as [CGFloat] {
                let stops = LyricPreviewFill.locations(progress: progress, edgeWidth: edge)
                XCTAssertEqual(stops.count, 4)
                XCTAssertEqual(stops.first, 0)
                XCTAssertEqual(stops.last, 1)
                XCTAssertEqual(stops, stops.sorted(),
                               "CAGradientLayer needs non-decreasing stops (progress \(progress), edge \(edge))")
                XCTAssertTrue(stops.allSatisfy { $0 >= 0 && $0 <= 1 })
            }
        }
    }

    /// At the end of a line `progress + edgeWidth` runs past 1.0; the soft edge
    /// has to collapse rather than push a stop out of range.
    func testFillLocationsClampTheSoftEdgeAtTheEnd() {
        let stops = LyricPreviewFill.locations(progress: 1.0, edgeWidth: 0.20)
        XCTAssertEqual(stops[1], 1.0)
        XCTAssertEqual(stops[2], 1.0)
    }

    // MARK: - Fitting the stage

    func testStageDoesNotZoomWhenThePillAlreadyFits() {
        XCTAssertEqual(LyricPreviewFit.scale(desiredWidth: 300, availableWidth: 476), 1)
        XCTAssertEqual(LyricPreviewFit.scale(desiredWidth: 476, availableWidth: 476), 1)
    }

    /// An overlay far wider than the stage is shown zoomed out rather than
    /// truncated — the real thing would have drawn the whole line.
    func testStageZoomsOutForAnOverlayWiderThanItself() {
        XCTAssertEqual(LyricPreviewFit.scale(desiredWidth: 952, availableWidth: 476), 0.5, accuracy: 0.0001)
    }

    func testScaleNeverEnlargesOrDividesByZero() {
        XCTAssertEqual(LyricPreviewFit.scale(desiredWidth: 100, availableWidth: 900), 1)
        XCTAssertEqual(LyricPreviewFit.scale(desiredWidth: 0, availableWidth: 476), 1)
        XCTAssertEqual(LyricPreviewFit.scale(desiredWidth: 476, availableWidth: 0), 1)
    }

    /// The samples have to fit an unscaled default theme, or the preview opens
    /// looking broken before anything is changed.
    func testSamplesFitTheStageAtDefaultThemeWithoutZooming() {
        let theme = Theme()
        let width = OverlayLayout.trackWidth(
            lineTexts: LyricPreviewSample.lines, secondaryTexts: [],
            currentFont: theme.currentLineFont, nextFont: theme.nextLineFont,
            letterSpacing: theme.letterSpacing, maxWidth: theme.overlayWidth)
        XCTAssertEqual(LyricPreviewFit.scale(desiredWidth: width, availableWidth: 476), 1,
                       "sample lines need \(width)pt, more than the stage shows at 1:1")
    }

    func testRestProgressSitsMidLineSoEdgeSoftnessIsVisible() {
        XCTAssertGreaterThan(LyricPreviewFill.restProgress, 0.2)
        XCTAssertLessThan(LyricPreviewFill.restProgress, 0.9)
    }
}
