import XCTest
import Combine
@testable import yalyricLib

/// Choosing a preset in Settings used to write the theme first and clear the
/// saved custom position afterwards. The overlay repositions on the theme
/// publish, so it still saw the custom flag and ignored the new preset.
final class OverlayPositionSelectionTests: XCTestCase {

    private var savedFlag = false
    private var savedPosition: OverlayPosition = .bottomCenter

    override func setUp() {
        super.setUp()
        savedFlag = AppConfig.get(AppConfig.Overlay.hasCustomPosition)
        savedPosition = ThemeManager.shared.theme.overlayPosition
    }

    override func tearDown() {
        AppConfig.set(AppConfig.Overlay.hasCustomPosition, savedFlag)
        ThemeManager.shared.theme.overlayPosition = savedPosition
        super.tearDown()
    }

    func testSelectingPresetClearsCustomPositionBeforeThemePublishes() {
        AppConfig.set(AppConfig.Overlay.hasCustomPosition, true)
        ThemeManager.shared.theme.overlayPosition = .bottomCenter

        var flagSeenByObserver: Bool?
        let sub = ThemeManager.shared.$theme.dropFirst().sink { _ in
            flagSeenByObserver = AppConfig.get(AppConfig.Overlay.hasCustomPosition)
        }
        defer { sub.cancel() }

        ThemeManager.shared.selectOverlayPosition(.center)

        XCTAssertEqual(flagSeenByObserver, false, "observers must see the custom flag already cleared")
        XCTAssertEqual(ThemeManager.shared.theme.overlayPosition, .center)
    }
}
