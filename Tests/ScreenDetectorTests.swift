// Tests/ScreenDetectorTests.swift
import XCTest
@testable import yalyricLib

final class ScreenDetectorTests: XCTestCase {

    func testDisplayBehaviorRawValues() {
        XCTAssertEqual(DisplayBehavior(rawValue: "Follow Mouse"), .followMouse)
        XCTAssertEqual(DisplayBehavior(rawValue: "Follow Focused Window"), .followFocusedWindow)
        XCTAssertEqual(DisplayBehavior(rawValue: "Pin to Screen"), .pinToScreen)
        XCTAssertEqual(DisplayBehavior(rawValue: "Show on All"), .showOnAll)
    }

    func testDisplayBehaviorInvalidRawValue() {
        XCTAssertNil(DisplayBehavior(rawValue: "Invalid"))
    }

    func testTargetScreenReturnsNonNil() {
        let screen = ScreenDetector.targetScreen(behavior: .followMouse, pinnedIndex: 0)
        XCTAssertNotNil(screen)
    }

    func testTargetScreenPinnedOutOfBounds() {
        let screen = ScreenDetector.targetScreen(behavior: .pinToScreen, pinnedIndex: 999)
        XCTAssertNotNil(screen)
    }

    func testAllScreensReturnsAtLeastOne() {
        XCTAssertFalse(ScreenDetector.allScreens().isEmpty)
    }

    func testRelativePositionRoundTrip() {
        let screen = NSScreen.screens[0]
        let vf = screen.visibleFrame
        let absPoint = NSPoint(x: vf.midX, y: vf.midY)
        let rel = ScreenDetector.absoluteToRelative(centerX: absPoint.x, originY: absPoint.y, on: screen)
        let back = ScreenDetector.relativeToAbsolute(relativeX: rel.relativeX, relativeY: rel.relativeY, on: screen)
        XCTAssertEqual(back.centerX, absPoint.x, accuracy: 1.0)
        XCTAssertEqual(back.originY, absPoint.y, accuracy: 1.0)
    }

    func testRelativePositionEdgeCases() {
        let screen = NSScreen.screens[0]
        let vf = screen.visibleFrame
        let rel = ScreenDetector.absoluteToRelative(centerX: vf.maxX, originY: vf.maxY, on: screen)
        XCTAssertEqual(rel.relativeX, 1.0, accuracy: 0.01)
        XCTAssertEqual(rel.relativeY, 1.0, accuracy: 0.01)
        let rel2 = ScreenDetector.absoluteToRelative(centerX: vf.minX, originY: vf.minY, on: screen)
        XCTAssertEqual(rel2.relativeX, 0.0, accuracy: 0.01)
        XCTAssertEqual(rel2.relativeY, 0.0, accuracy: 0.01)
    }
}
