import XCTest
import AppKit
@testable import yalyricLib

/// A line change arriving while the previous transition is still running.
///
/// The A/B pair recycles the outgoing label as the next incoming one. If that
/// label is still visible when its text is assigned, the previous line is
/// substituted in place instead of fading out — the text changes under the
/// reader at roughly half opacity. Playback polls every 0.5s and the transition
/// also runs 0.5s, so the two collide regularly.
final class OverlayInterruptedTransitionTests: XCTestCase {

    private var savedStyle: TransitionStyle = .crossfade
    private var savedDuration: TimeInterval = 0.5

    override func setUp() {
        super.setUp()
        savedStyle = ThemeManager.shared.theme.transitionStyle
        savedDuration = ThemeManager.shared.theme.animationDuration
        ThemeManager.shared.theme.transitionStyle = .slideUp
        ThemeManager.shared.theme.animationDuration = 0.5
    }

    override func tearDown() {
        ThemeManager.shared.theme.transitionStyle = savedStyle
        ThemeManager.shared.theme.animationDuration = savedDuration
        super.tearDown()
    }

    private func pump(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    private func onScreenOpacity(of text: String, in window: OverlayWindow) -> Float? {
        guard let label = window.currentLineLabels.first(where: { $0.stringValue == text })
        else { return nil }
        return label.layer?.presentation()?.opacity
    }

    func testNewLineIsNotRevealedInAStillVisibleLabel() throws {
        let window = OverlayWindow()
        window.updateLyrics(current: "line one", next: "second one")
        pump(1.2)

        window.updateLyrics(current: "line two", next: "second two")
        pump(0.25)  // interrupt mid-transition, while the outgoing label is ~50% visible

        window.updateLyrics(current: "line three", next: "second three")
        pump(0.04)

        let opacity = try XCTUnwrap(onScreenOpacity(of: "line three", in: window),
                                    "the incoming label should be holding the new line")
        XCTAssertLessThanOrEqual(
            opacity, 0.10,
            "the new line must not appear in a label that is still visibly showing the previous one")
    }

    func testInterruptedTransitionStillSettlesOnTheLatestLine() throws {
        let window = OverlayWindow()
        window.updateLyrics(current: "line one", next: "second one")
        pump(1.2)

        window.updateLyrics(current: "line two", next: "second two")
        pump(0.25)
        window.updateLyrics(current: "line three", next: "second three")
        pump(1.0)

        let opacity = try XCTUnwrap(onScreenOpacity(of: "line three", in: window))
        XCTAssertGreaterThan(opacity, 0.9, "the latest line must end up fully visible")
    }
}
