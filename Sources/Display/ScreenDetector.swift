// Sources/Display/ScreenDetector.swift
import AppKit

enum DisplayBehavior: String, CaseIterable {
    case followMouse = "Follow Mouse"
    case followFocusedWindow = "Follow Focused Window"
    case pinToScreen = "Pin to Screen"
    case showOnAll = "Show on All"
}

enum ScreenDetector {

    /// Returns the target screen for single-window modes.
    static func targetScreen(behavior: DisplayBehavior, pinnedIndex: Int) -> NSScreen {
        switch behavior {
        case .followMouse:
            return screenUnderMouse()
        case .followFocusedWindow:
            return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        case .pinToScreen:
            let screens = NSScreen.screens
            if pinnedIndex >= 0 && pinnedIndex < screens.count {
                return screens[pinnedIndex]
            }
            return NSScreen.main ?? screens.first ?? NSScreen()
        case .showOnAll:
            return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        }
    }

    /// Returns all connected screens.
    static func allScreens() -> [NSScreen] {
        NSScreen.screens
    }

    /// Screen containing the mouse cursor.
    static func screenUnderMouse() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    // MARK: - Relative Position Conversion

    /// Convert absolute screen coordinates to relative (0.0–1.0) within visibleFrame.
    static func absoluteToRelative(centerX: CGFloat, originY: CGFloat, on screen: NSScreen) -> (relativeX: CGFloat, relativeY: CGFloat) {
        let vf = screen.visibleFrame
        let rx = vf.width > 0 ? (centerX - vf.origin.x) / vf.width : 0.5
        let ry = vf.height > 0 ? (originY - vf.origin.y) / vf.height : 0.5
        return (relativeX: rx, relativeY: ry)
    }

    /// Convert relative coordinates back to absolute for a given screen.
    static func relativeToAbsolute(relativeX: CGFloat, relativeY: CGFloat, on screen: NSScreen) -> (centerX: CGFloat, originY: CGFloat) {
        let vf = screen.visibleFrame
        let cx = vf.origin.x + relativeX * vf.width
        let oy = vf.origin.y + relativeY * vf.height
        return (centerX: cx, originY: oy)
    }
}
