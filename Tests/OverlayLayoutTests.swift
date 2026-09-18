import XCTest
import AppKit
@testable import yalyricLib

/// Pure layout math for the lyrics overlay. Regression cases come from three
/// confirmed defects: labels sized to the raw glyph width truncate with an
/// ellipsis, letter spacing was measured but dropped on render, and the text
/// block sat above the window's vertical centre.
final class OverlayLayoutTests: XCTestCase {

    private let font = NSFont.systemFont(ofSize: 24, weight: .semibold)
    private let sample = "And I will always love you, my darling dear"

    // MARK: - Text styling

    func testAttributedTextKeepsLetterSpacingAndCenterAlignment() {
        let str = OverlayLayout.attributedText(sample, font: font, letterSpacing: 1.5)
        let kern = str.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
        let style = str.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(kern, 1.5)
        XCTAssertEqual(style?.alignment, .center)
        XCTAssertEqual(str.string, sample)
    }

    // MARK: - Width measurement

    func testRequiredLabelWidthExceedsRawGlyphWidth() {
        let raw = ceil((sample as NSString).size(withAttributes: [.font: font]).width)
        let required = OverlayLayout.requiredLabelWidth(for: sample, font: font, letterSpacing: 0)
        XCTAssertGreaterThan(required, raw, "NSTextField needs room beyond the glyph run or it truncates")
    }

    func testLabelAtRequiredWidthDoesNotTruncate() {
        let required = OverlayLayout.requiredLabelWidth(for: sample, font: font, letterSpacing: 0)
        let tight = inkSpan(width: required)
        let roomy = inkSpan(width: required + 200)
        XCTAssertEqual(tight, roomy, accuracy: 2, "ellipsis truncation shortens the drawn glyph run")
    }

    func testWindowWidthPadsWidestLineAndClamps() {
        XCTAssertEqual(OverlayLayout.windowWidth(currentTextWidth: 300, nextTextWidth: 100, maxWidth: 800), 332)
        XCTAssertEqual(OverlayLayout.windowWidth(currentTextWidth: 50, nextTextWidth: 20, maxWidth: 800), 200)
        XCTAssertEqual(OverlayLayout.windowWidth(currentTextWidth: 900, nextTextWidth: 0, maxWidth: 800), 800)
    }

    // MARK: - Vertical layout

    func testVerticalLayoutCentersTextBlockInWindow() {
        let v = OverlayLayout.vertical(currentLineHeight: 28, nextLineHeight: 19)
        let block = 28 + OverlayLayout.lineGap + 19
        XCTAssertEqual(v.currentTop + block / 2, v.height / 2, accuracy: 0.5)
        XCTAssertEqual(v.nextTop, v.currentTop + 28 + OverlayLayout.lineGap)
        XCTAssertGreaterThanOrEqual(v.height, OverlayLayout.minHeight)
    }

    func testVerticalLayoutGrowsWindowForLargeFontsWithoutOverlap() {
        let v = OverlayLayout.vertical(currentLineHeight: 48, nextLineHeight: 30)
        XCTAssertGreaterThanOrEqual(v.nextTop, v.currentTop + 48)
        XCTAssertGreaterThan(v.height, OverlayLayout.minHeight)
        XCTAssertLessThanOrEqual(v.nextTop + 30, v.height)
    }

    // MARK: - Karaoke mask

    func testKaraokeMaskFrameSpansTextCenteredInLabel() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 30)
        let frame = OverlayLayout.karaokeMaskFrame(labelBounds: bounds, textWidth: 200)
        XCTAssertEqual(frame, CGRect(x: 200, y: 0, width: 200, height: 30))
    }

    func testKaraokeMaskFrameClampsToLabel() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 30)
        let frame = OverlayLayout.karaokeMaskFrame(labelBounds: bounds, textWidth: 900)
        XCTAssertEqual(frame, bounds)
    }

    // MARK: - Window frame resolution

    private let screenFrame = CGRect(x: 100, y: 0, width: 1000, height: 900)
    private let visibleFrame = CGRect(x: 100, y: 50, width: 1000, height: 800)

    func testCenterPresetCentersOnVisibleFrame() {
        var theme = Theme()
        theme.overlayPosition = .center
        theme.overlayWidth = 800
        let f = OverlayLayout.frame(theme: theme, custom: nil, screenFrame: screenFrame, visibleFrame: visibleFrame, height: 90)
        XCTAssertEqual(f.midX, 600)
        XCTAssertEqual(f.midY, 450)
        XCTAssertEqual(f.width, 800)
    }

    func testCustomRelativePositionOverridesPreset() {
        var theme = Theme()
        theme.overlayPosition = .topCenter
        theme.overlayWidth = 800
        let custom = OverlayLayout.CustomPosition(relativeX: 0.25, relativeY: 0.5)
        let f = OverlayLayout.frame(theme: theme, custom: custom, screenFrame: screenFrame, visibleFrame: visibleFrame, height: 90)
        XCTAssertEqual(f.midX, 350)
        XCTAssertEqual(f.minY, 450)
    }

    func testBarStyleSpansScreenEvenWithCustomPosition() {
        var theme = Theme()
        theme.backgroundStyle = .bar
        let custom = OverlayLayout.CustomPosition(relativeX: 0.25, relativeY: 0.5)
        let f = OverlayLayout.frame(theme: theme, custom: custom, screenFrame: screenFrame, visibleFrame: visibleFrame, height: 90)
        XCTAssertEqual(f.minX, screenFrame.minX)
        XCTAssertEqual(f.width, screenFrame.width)
        XCTAssertEqual(f.minY, 450)
    }

    func testLegacyAbsoluteCustomPositionIsConvertedToRelative() {
        let migrated = OverlayLayout.customPosition(rawX: 350, rawY: 450, visibleFrame: visibleFrame)
        XCTAssertEqual(migrated.relativeX, 0.25, accuracy: 0.0001)
        XCTAssertEqual(migrated.relativeY, 0.5, accuracy: 0.0001)
        let already = OverlayLayout.customPosition(rawX: 0.3, rawY: 0.4, visibleFrame: visibleFrame)
        XCTAssertEqual(already.relativeX, 0.3)
        XCTAssertEqual(already.relativeY, 0.4)
    }

    // MARK: - Helpers

    /// Width in points of the drawn glyph run for a label of the given width.
    private func inkSpan(width: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = OverlayLayout.attributedText(sample, font: font, letterSpacing: 0)
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 0, y: 0, width: width, height: 40)
        guard let rep = label.bitmapImageRepForCachingDisplay(in: label.bounds) else { return -1 }
        label.cacheDisplay(in: label.bounds, to: rep)
        var minX = Int.max, maxX = -1
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                minX = min(minX, x); maxX = max(maxX, x)
            }
        }
        guard maxX >= 0 else { return 0 }
        return CGFloat(maxX - minX + 1) * width / CGFloat(rep.pixelsWide)
    }
}
