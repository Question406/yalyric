import XCTest
@testable import yalyricLib

final class HotkeyTests: XCTestCase {

    // MARK: - Modifier Parsing

    func testParseCtrlOpt() {
        let result = ShortcutParser.parse("ctrl+opt+l")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.modifiers, ShortcutParser.controlKey | ShortcutParser.optionKey)
    }

    func testParseCmdShift() {
        let result = ShortcutParser.parse("cmd+shift+a")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.modifiers, ShortcutParser.cmdKey | ShortcutParser.shiftKey)
    }

    func testParseAllModifiers() {
        let result = ShortcutParser.parse("ctrl+opt+cmd+shift+x")
        XCTAssertNotNil(result)
        let expected = ShortcutParser.controlKey | ShortcutParser.optionKey | ShortcutParser.cmdKey | ShortcutParser.shiftKey
        XCTAssertEqual(result!.modifiers, expected)
    }

    // MARK: - Key Code Parsing

    func testParseLetterKey() {
        let result = ShortcutParser.parse("ctrl+opt+l")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x25) // kVK_ANSI_L
    }

    func testParseNumberKey() {
        let result = ShortcutParser.parse("ctrl+opt+0")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x1D) // kVK_ANSI_0
    }

    func testParseArrowRight() {
        let result = ShortcutParser.parse("ctrl+opt+right")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x7C) // kVK_RightArrow
    }

    func testParseArrowLeft() {
        let result = ShortcutParser.parse("ctrl+opt+left")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x7B) // kVK_LeftArrow
    }

    func testParseHKey() {
        let result = ShortcutParser.parse("ctrl+opt+h")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x04) // kVK_ANSI_H
    }

    // MARK: - Edge Cases

    func testParseEmptyString() {
        let result = ShortcutParser.parse("")
        XCTAssertNil(result)
    }

    func testParseNoModifiers() {
        let result = ShortcutParser.parse("l")
        XCTAssertNil(result)
    }

    func testParseUnknownKey() {
        let result = ShortcutParser.parse("ctrl+opt+banana")
        XCTAssertNil(result)
    }

    func testParseCaseInsensitive() {
        let result = ShortcutParser.parse("Ctrl+Opt+L")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x25) // kVK_ANSI_L
    }

    // MARK: - Display String

    func testDisplayString() {
        XCTAssertEqual(ShortcutParser.displayString("ctrl+opt+l"), "⌃⌥L")
        XCTAssertEqual(ShortcutParser.displayString("ctrl+opt+right"), "⌃⌥→")
        XCTAssertEqual(ShortcutParser.displayString("ctrl+opt+0"), "⌃⌥0")
        XCTAssertEqual(ShortcutParser.displayString("cmd+shift+a"), "⇧⌘A")
    }
}
