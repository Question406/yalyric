import XCTest
import AppKit
@testable import yalyricLib

/// After a line change the previous text stays in the faded-out label. Its
/// compression resistance outranked the window's size priority, so Auto Layout
/// held the window at the old width while the origin moved to the new target:
/// the overlay grew to the right and the lyric sat off centre.
final class OverlayWindowTests: XCTestCase {

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

    func testWindowShrinksAndStaysCentredWhenNextLineIsShorter() {
        let window = OverlayWindow()
        let centre = window.frame.midX

        window.updateLyrics(current: "a very long line of lyrics that is much wider than the one after it", next: "")
        window.layoutIfNeeded()
        let wide = window.frame.width
        XCTAssertGreaterThan(wide, OverlayLayout.minWidth)

        window.updateLyrics(current: "short", next: "")
        window.layoutIfNeeded()

        XCTAssertEqual(window.frame.width, OverlayLayout.minWidth, accuracy: 1, "window must shrink to the new line")
        XCTAssertEqual(window.frame.midX, centre, accuracy: 1, "window must stay centred on its anchor")
    }

    func testWindowNeverExceedsThemeMaxWidth() {
        let window = OverlayWindow()
        window.updateLyrics(current: String(repeating: "wide lyrics ", count: 30), next: "")
        window.layoutIfNeeded()
        XCTAssertLessThanOrEqual(window.frame.width, 800 + 1)
    }
}
