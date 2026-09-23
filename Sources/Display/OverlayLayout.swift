// Sources/Display/OverlayLayout.swift
import AppKit

/// Pure layout math for `OverlayWindow`. Everything here is deterministic and
/// screen-independent so it can be unit tested without creating windows.
enum OverlayLayout {

    /// Horizontal inset between the window edge and each label.
    static let horizontalPadding: CGFloat = 16
    /// Narrowest the overlay will shrink to, so a one-word line still looks like a pill.
    static let minWidth: CGFloat = 200
    /// Shortest window height; taller when the fonts need it.
    static let minHeight: CGFloat = 90
    /// Space between the bottom of the current line and the top of the next line.
    static let lineGap: CGFloat = 6
    /// Minimum space above and below the text block.
    static let verticalPadding: CGFloat = 12

    // MARK: - Text

    /// The string every overlay label displays: centred and carrying the theme's
    /// letter spacing. Setting a plain `stringValue` drops the kern, which made
    /// the measured width disagree with the drawn one.
    static func attributedText(_ text: String, font: NSFont, letterSpacing: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        if letterSpacing != 0 { attrs[.kern] = letterSpacing }
        return NSAttributedString(string: text, attributes: attrs)
    }

    /// Width a single-line `NSTextField` needs to draw `text` without tail
    /// truncation. `NSTextFieldCell` pads the glyph run on both sides, so the raw
    /// `NSString.size` measurement is a few points short and produces an ellipsis.
    static func requiredLabelWidth(for text: String, font: NSFont, letterSpacing: CGFloat) -> CGFloat {
        requiredLabelSize(for: text, font: font, letterSpacing: letterSpacing).width
    }

    static func requiredLabelSize(for text: String, font: NSFont, letterSpacing: CGFloat) -> CGSize {
        let cell = NSTextFieldCell()
        cell.isBezeled = false
        cell.isBordered = false
        cell.wraps = false
        cell.font = font
        cell.attributedStringValue = attributedText(text.isEmpty ? " " : text, font: font, letterSpacing: letterSpacing)
        let size = cell.cellSize
        return CGSize(width: text.isEmpty ? 0 : ceil(size.width), height: ceil(size.height))
    }

    /// Window width for the two visible lines, padded and clamped.
    static func windowWidth(currentTextWidth: CGFloat, nextTextWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        let text = max(currentTextWidth, nextTextWidth)
        return min(maxWidth, max(minWidth, text + horizontalPadding * 2))
    }

    /// Width that fits every line of a whole track, so the window can be sized
    /// once when lyrics load rather than following each line.
    ///
    /// Tracking the text meant resizing 75–175pt on every line change. That was
    /// smooth — a clean 60fps — but the pill visibly grew and shrank and the
    /// centred lyric slid sideways for the length of each crossfade. Bilingual
    /// lyrics made it far worse, because the width came from the wider of an
    /// original line and its translation, and the two scripts have very
    /// different metrics.
    ///
    /// `secondaryTexts` are measured in the next-line font because that is the
    /// slot they occupy; they still have to count, or a long translation would
    /// truncate for the entire song.
    static func trackWidth(lineTexts: [String], secondaryTexts: [String],
                           currentFont: NSFont, nextFont: NSFont,
                           letterSpacing: CGFloat, maxWidth: CGFloat) -> CGFloat {
        var widest: CGFloat = 0
        for text in lineTexts {
            widest = max(widest, requiredLabelWidth(for: text, font: currentFont, letterSpacing: letterSpacing))
        }
        for text in secondaryTexts {
            widest = max(widest, requiredLabelWidth(for: text, font: nextFont, letterSpacing: letterSpacing))
        }
        return min(maxWidth, max(minWidth, widest + horizontalPadding * 2))
    }

    // MARK: - Vertical layout

    struct Vertical: Equatable {
        /// Window height.
        let height: CGFloat
        /// Distance from the top of the window to the top of the current line.
        let currentTop: CGFloat
        /// Distance from the top of the window to the top of the next line.
        let nextTop: CGFloat
    }

    /// Centres the current+next text block vertically. The window grows when the
    /// fonts need more room instead of letting the lines overlap.
    static func vertical(currentLineHeight: CGFloat, nextLineHeight: CGFloat) -> Vertical {
        let block = currentLineHeight + lineGap + nextLineHeight
        let height = max(minHeight, ceil(block + verticalPadding * 2))
        let currentTop = (height - block) / 2
        return Vertical(height: height, currentTop: currentTop, nextTop: currentTop + currentLineHeight + lineGap)
    }

    // MARK: - Karaoke fill

    /// The gradient mask should sweep the text's own extent, not the whole label.
    /// Labels are as wide as the widest of the two lines, so a short line over a
    /// long one would otherwise fill through empty space first.
    static func karaokeMaskFrame(labelBounds: CGRect, textWidth: CGFloat) -> CGRect {
        let width = min(max(0, textWidth), labelBounds.width)
        return CGRect(x: labelBounds.midX - width / 2, y: labelBounds.minY, width: width, height: labelBounds.height)
    }

    // MARK: - Window frame

    /// A user-dragged position, stored relative to a screen's visible frame.
    struct CustomPosition: Equatable {
        var relativeX: CGFloat  // 0...1 across visibleFrame, marks the window's centre
        var relativeY: CGFloat  // 0...1 up visibleFrame, marks the window's bottom edge
    }

    /// Older builds stored absolute screen points. Anything beyond 1.0 is treated
    /// as absolute and converted against the given visible frame.
    static func customPosition(rawX: CGFloat, rawY: CGFloat, visibleFrame vf: CGRect) -> CustomPosition {
        guard rawX > 1.0 || rawY > 1.0 else {
            return CustomPosition(relativeX: rawX, relativeY: rawY)
        }
        let rx = vf.width > 0 ? (rawX - vf.minX) / vf.width : 0.5
        let ry = vf.height > 0 ? (rawY - vf.minY) / vf.height : 0.5
        return CustomPosition(relativeX: rx, relativeY: ry)
    }

    /// The one place that decides where the overlay sits on a screen. A custom
    /// position wins over the preset; the bar style always spans the screen.
    static func frame(theme: Theme, custom: CustomPosition?, screenFrame: CGRect, visibleFrame: CGRect, height: CGFloat) -> CGRect {
        let isBar = theme.backgroundStyle == .bar
        let width = isBar ? screenFrame.width : theme.overlayWidth
        let size = CGSize(width: width, height: height)

        var origin: CGPoint
        if let custom {
            let centerX = visibleFrame.minX + custom.relativeX * visibleFrame.width
            let y = visibleFrame.minY + custom.relativeY * visibleFrame.height
            origin = CGPoint(x: centerX - width / 2, y: y)
        } else {
            origin = theme.overlayPosition.defaultOrigin(visibleFrame: visibleFrame, overlaySize: size)
        }
        if isBar { origin.x = screenFrame.minX }
        return CGRect(origin: origin, size: size)
    }
}
