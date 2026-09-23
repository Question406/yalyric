import XCTest
import AppKit
@testable import yalyricLib

/// The second line's dimming used to be applied twice — once baked into the
/// text colour's alpha, once as the view's `alphaValue` — and the two multiply.
/// The label was created without an explicit `alphaValue`, so it started at
/// 1.0 × 0.5 = 0.5 and dropped to 0.5 × 0.5 = 0.25 the first time a line
/// changed: a visible brightness cliff on the first transition that never
/// recovered for the rest of the track.
final class OverlaySecondLineOpacityTests: XCTestCase {

    private var savedStyle: TransitionStyle = .crossfade
    private var savedOpacity: CGFloat = 0.5

    override func setUp() {
        super.setUp()
        savedStyle = ThemeManager.shared.theme.transitionStyle
        savedOpacity = ThemeManager.shared.theme.nextLineOpacity
        ThemeManager.shared.theme.transitionStyle = .none
        ThemeManager.shared.theme.nextLineOpacity = 0.5
    }

    override func tearDown() {
        ThemeManager.shared.theme.transitionStyle = savedStyle
        ThemeManager.shared.theme.nextLineOpacity = savedOpacity
        super.tearDown()
    }

    /// Opacity must come from exactly one multiplier, so it cannot compound.
    private func effectiveOpacity(_ window: OverlayWindow) -> CGFloat {
        let label = window.secondLineLabel
        return (label.textColor?.alphaComponent ?? 1) * label.alphaValue
    }

    /// Lets the queued fade-out completion handler and its fade-in run.
    private func settle() {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    func testSecondLineStartsAtTheThemeOpacity() {
        let window = OverlayWindow()
        XCTAssertEqual(effectiveOpacity(window), 0.5, accuracy: 0.01)
    }

    func testSecondLineKeepsTheSameOpacityAfterALineChange() {
        let window = OverlayWindow()
        window.updateLyrics(current: "first line", next: "second line one")
        settle()

        XCTAssertEqual(effectiveOpacity(window), 0.5, accuracy: 0.01,
                       "the second line must not get dimmer just because a line changed")
    }

    func testSecondLineOpacityIsStableAcrossSeveralLineChanges() {
        let window = OverlayWindow()
        window.updateLyrics(current: "first line", next: "second line one")
        settle()
        let after1 = effectiveOpacity(window)

        window.updateLyrics(current: "second line", next: "second line two")
        settle()
        let after2 = effectiveOpacity(window)

        XCTAssertEqual(after1, 0.5, accuracy: 0.01)
        XCTAssertEqual(after2, 0.5, accuracy: 0.01)
    }
}
