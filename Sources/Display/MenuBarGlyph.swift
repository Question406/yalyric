import AppKit

/// The status-bar version of the app icon (`assets/icon.svg`): the geometric note over a
/// partly sung lyric line. The translation line is left out, since it would be under 2 pt tall.
/// It is a template image, so AppKit tints it for light, dark and highlighted menu bars.
enum MenuBarGlyph {
    static let size = NSSize(width: 18, height: 18)

    static func image() -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()

            // Note: circle head, straight stem, quarter-ring flag (the icon's proportions at 1/30).
            NSBezierPath(ovalIn: NSRect(x: 1, y: 7, width: 5, height: 5)).fill()
            NSBezierPath(rect: NSRect(x: 4.33, y: 1, width: 1.67, height: 8.5)).fill()
            let flag = NSBezierPath()
            flag.move(to: NSPoint(x: 6, y: 1))
            flag.appendArc(withCenter: NSPoint(x: 6, y: 6), radius: 5, startAngle: 270, endAngle: 0, clockwise: false)
            flag.line(to: NSPoint(x: 9.33, y: 6))
            flag.appendArc(withCenter: NSPoint(x: 6, y: 6), radius: 3.33, startAngle: 0, endAngle: 270, clockwise: true)
            flag.close()
            flag.fill()

            // Lyric line: the sung part solid, the rest faint.
            let line = NSRect(x: 1, y: 13.5, width: 16, height: 3)
            NSColor.black.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: line, xRadius: 1.5, yRadius: 1.5).fill()
            NSColor.black.setFill()
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 11, height: size.height)).addClip()
            NSBezierPath(roundedRect: line, xRadius: 1.5, yRadius: 1.5).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "yalyric"
        return image
    }
}
