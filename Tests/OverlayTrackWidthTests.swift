import XCTest
import AppKit
@testable import yalyricLib

/// Sizing the overlay once per track instead of once per line.
///
/// Tracking the text meant the window resized 75–175pt on every line change —
/// smooth at 60fps, but the pill visibly grew and shrank and the centred lyric
/// slid sideways throughout each crossfade. Measuring the whole track up front
/// removes the motion entirely. Fixture text is invented.
final class OverlayTrackWidthTests: XCTestCase {

    private let current = NSFont.systemFont(ofSize: 24, weight: .bold)
    private let next = NSFont.systemFont(ofSize: 16, weight: .bold)

    private func trackWidth(_ lines: [String], _ secondary: [String] = [],
                            maxWidth: CGFloat = 800) -> CGFloat {
        OverlayLayout.trackWidth(lineTexts: lines, secondaryTexts: secondary,
                                 currentFont: current, nextFont: next,
                                 letterSpacing: 0, maxWidth: maxWidth)
    }

    func testSizesToTheWidestLineInTheTrack() {
        let narrow = trackWidth(["short"])
        let wide = trackWidth(["short", "a considerably longer line than the first one"])
        XCTAssertGreaterThan(wide, narrow)
    }

    func testOrderOfLinesDoesNotMatter() {
        let a = trackWidth(["short", "a considerably longer line than the first one"])
        let b = trackWidth(["a considerably longer line than the first one", "short"])
        XCTAssertEqual(a, b, accuracy: 0.5)
    }

    /// A translation occupies the second slot, so it has to count toward the
    /// width too — otherwise it would truncate for the whole song.
    func testSecondaryTextsCountTowardTheWidth() {
        let withoutSecondary = trackWidth(["short"])
        let withSecondary = trackWidth(["short"], ["a much longer translation line for this lyric"])
        XCTAssertGreaterThan(withSecondary, withoutSecondary)
    }

    func testNeverExceedsTheThemeMaximum() {
        let w = trackWidth([String(repeating: "very long lyric ", count: 40)], maxWidth: 600)
        XCTAssertLessThanOrEqual(w, 600)
    }

    func testNeverNarrowerThanTheMinimum() {
        XCTAssertGreaterThanOrEqual(trackWidth(["x"]), OverlayLayout.minWidth)
        XCTAssertGreaterThanOrEqual(trackWidth([]), OverlayLayout.minWidth)
    }

    /// The whole point: one width for the track, so no line change moves it.
    func testWidthIsStableAcrossEveryLineOfTheTrack() {
        let lines = ["short", "a considerably longer line than the first one", "mid length line"]
        let full = trackWidth(lines)
        for line in lines {
            XCTAssertEqual(trackWidth(lines, [line]), full, accuracy: 0.5,
                           "no single line may change the track's width")
        }
    }
}

/// The window itself, once sized for a track.
final class OverlayPinnedWidthTests: XCTestCase {

    private var savedStyle: TransitionStyle = .crossfade
    private var savedWidth: CGFloat = 800

    override func setUp() {
        super.setUp()
        savedStyle = ThemeManager.shared.theme.transitionStyle
        savedWidth = ThemeManager.shared.theme.overlayWidth
        ThemeManager.shared.theme.transitionStyle = .none
        ThemeManager.shared.theme.overlayWidth = 800
    }

    override func tearDown() {
        ThemeManager.shared.theme.transitionStyle = savedStyle
        ThemeManager.shared.theme.overlayWidth = savedWidth
        super.tearDown()
    }

    private func lyrics(_ texts: [String]) -> Lyrics {
        Lyrics(lines: texts.enumerated().map { LyricLine(time: Double($0.offset), text: $0.element) },
               source: .netease, isSynced: true)
    }

    func testWidthDoesNotChangeBetweenLinesOnceTrackIsPinned() {
        let window = OverlayWindow()
        let texts = ["short", "a considerably longer line than the other ones here", "mid length"]
        window.pinTrackWidth(for: lyrics(texts), secondary: .nextLine)
        window.layoutIfNeeded()
        let pinned = window.frame.width

        for (i, text) in texts.enumerated() {
            window.updateLyrics(current: text, next: texts[(i + 1) % texts.count])
            window.layoutIfNeeded()
            XCTAssertEqual(window.frame.width, pinned, accuracy: 1,
                           "line '\(text)' must not resize the window")
        }
    }

    /// The window still has to be wide enough for the track's longest line.
    func testPinnedWidthFitsTheLongestLine() {
        let window = OverlayWindow()
        let long = "a considerably longer line than the other ones here"
        window.pinTrackWidth(for: lyrics(["short", long]), secondary: .nextLine)
        window.layoutIfNeeded()

        let needed = OverlayLayout.requiredLabelWidth(
            for: long, font: ThemeManager.shared.theme.currentLineFont,
            letterSpacing: ThemeManager.shared.theme.letterSpacing)
        XCTAssertGreaterThanOrEqual(window.frame.width, needed)
    }

    /// Translations sit in the second slot, so they must be measured too.
    func testTranslationsAreIncludedWhenTranslationModeIsActive() {
        let long = "a translation line that is far longer than any original here"
        let bilingual = Lyrics(lines: [
            LyricLine(time: 0, text: "short", translation: long)
        ], source: .netease, isSynced: true)

        let plain = OverlayWindow()
        plain.pinTrackWidth(for: bilingual, secondary: .nextLine)
        plain.layoutIfNeeded()

        let translated = OverlayWindow()
        translated.pinTrackWidth(for: bilingual, secondary: .translation)
        translated.layoutIfNeeded()

        XCTAssertGreaterThan(translated.frame.width, plain.frame.width)
    }
}
