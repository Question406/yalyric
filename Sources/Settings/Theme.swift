import AppKit
import Combine

// MARK: - Enums

enum TransitionStyle: String, CaseIterable {
    case slideUp = "Slide Up"
    case crossfade = "Crossfade"
    case scaleFade = "Scale Fade"
    case push = "Push"
    case none = "None"
}

enum BackgroundStyle: String, CaseIterable {
    case none = "None (Transparent)"
    case pill = "Rounded Pill"
    case bar = "Full-Width Bar"
}

enum OverlayPosition: String, CaseIterable {
    case bottomCenter = "Bottom Center"
    case topCenter = "Top Center"
    case center = "Center"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    case custom = "Custom"

    func defaultOrigin(for screen: NSScreen, overlaySize: NSSize) -> NSPoint {
        let frame = screen.visibleFrame
        switch self {
        case .bottomCenter:
            return NSPoint(x: frame.midX - overlaySize.width / 2, y: frame.minY + 80)
        case .topCenter:
            return NSPoint(x: frame.midX - overlaySize.width / 2, y: frame.maxY - overlaySize.height - 40)
        case .center:
            return NSPoint(x: frame.midX - overlaySize.width / 2, y: frame.midY - overlaySize.height / 2)
        case .bottomLeft:
            return NSPoint(x: frame.minX + 40, y: frame.minY + 80)
        case .bottomRight:
            return NSPoint(x: frame.maxX - overlaySize.width - 40, y: frame.minY + 80)
        case .custom:
            return NSPoint(x: frame.midX - overlaySize.width / 2, y: frame.minY + 80)
        }
    }
}

// MARK: - Theme

struct Theme: Equatable {
    // Typography
    var fontName: String = ""  // empty = system font
    var currentLineFontSize: CGFloat = 24
    var nextLineFontSize: CGFloat = 16
    var fontWeight: NSFont.Weight = .bold
    var letterSpacing: CGFloat = 0

    // Colors
    var textColor: NSColor = .white
    var nextLineOpacity: CGFloat = 0.5
    var shadowColor: NSColor = NSColor.black.withAlphaComponent(0.8)
    var shadowBlurRadius: CGFloat = 4
    var shadowOffset: NSSize = NSSize(width: 0, height: -1)

    // Background
    var backgroundStyle: BackgroundStyle = .none
    var backgroundColor: NSColor = NSColor.black.withAlphaComponent(0.5)
    var backgroundCornerRadius: CGFloat = 12

    // Animation
    var transitionStyle: TransitionStyle = .slideUp
    var animationDuration: TimeInterval = 0.3

    // Layout
    var overlayPosition: OverlayPosition = .bottomCenter
    var overlayWidth: CGFloat = 800

    // Computed
    var currentLineFont: NSFont {
        if fontName.isEmpty {
            return NSFont.systemFont(ofSize: currentLineFontSize, weight: fontWeight)
        }
        return NSFont(name: fontName, size: currentLineFontSize)
            ?? NSFont.systemFont(ofSize: currentLineFontSize, weight: fontWeight)
    }

    var nextLineFont: NSFont {
        if fontName.isEmpty {
            return NSFont.systemFont(ofSize: nextLineFontSize, weight: .medium)
        }
        return NSFont(name: fontName, size: nextLineFontSize)
            ?? NSFont.systemFont(ofSize: nextLineFontSize, weight: .medium)
    }

    var textShadow: NSShadow {
        let s = NSShadow()
        s.shadowColor = shadowColor
        s.shadowBlurRadius = shadowBlurRadius
        s.shadowOffset = shadowOffset
        return s
    }

    static func == (lhs: Theme, rhs: Theme) -> Bool {
        lhs.fontName == rhs.fontName
            && lhs.currentLineFontSize == rhs.currentLineFontSize
            && lhs.nextLineFontSize == rhs.nextLineFontSize
            && lhs.letterSpacing == rhs.letterSpacing
            && lhs.textColor == rhs.textColor
            && lhs.nextLineOpacity == rhs.nextLineOpacity
            && lhs.backgroundStyle == rhs.backgroundStyle
            && lhs.backgroundCornerRadius == rhs.backgroundCornerRadius
            && lhs.transitionStyle == rhs.transitionStyle
            && lhs.animationDuration == rhs.animationDuration
            && lhs.overlayPosition == rhs.overlayPosition
            && lhs.overlayWidth == rhs.overlayWidth
            && lhs.shadowBlurRadius == rhs.shadowBlurRadius
    }
}

// MARK: - ThemeManager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var theme: Theme {
        didSet { save() }
    }

    // Built-in presets
    static let presets: [(name: String, theme: Theme)] = [
        ("Classic", Theme()),
        ("Neon", {
            var t = Theme()
            t.textColor = NSColor(red: 0.4, green: 1.0, blue: 0.8, alpha: 1.0)
            t.shadowColor = NSColor(red: 0.0, green: 1.0, blue: 0.6, alpha: 0.6)
            t.shadowBlurRadius = 12
            t.backgroundStyle = .pill
            t.backgroundColor = NSColor.black.withAlphaComponent(0.7)
            return t
        }()),
        ("Minimal", {
            var t = Theme()
            t.currentLineFontSize = 16
            t.nextLineFontSize = 12
            t.fontWeight = .regular
            t.textColor = NSColor.white.withAlphaComponent(0.7)
            t.nextLineOpacity = 0.3
            t.overlayPosition = .bottomLeft
            return t
        }()),
        ("Karaoke", {
            var t = Theme()
            t.currentLineFontSize = 32
            t.nextLineFontSize = 20
            t.overlayPosition = .center
            t.backgroundStyle = .bar
            t.backgroundColor = NSColor.black.withAlphaComponent(0.6)
            return t
        }()),
        ("Spotify", {
            var t = Theme()
            t.textColor = NSColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 1.0)
            t.backgroundStyle = .pill
            t.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 0.9)
            t.backgroundCornerRadius = 8
            return t
        }()),
        ("Terminal", {
            var t = Theme()
            t.fontName = "SF Mono"
            t.currentLineFontSize = 18
            t.nextLineFontSize = 14
            t.fontWeight = .regular
            t.textColor = NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
            t.transitionStyle = .none
            t.backgroundStyle = .pill
            t.backgroundColor = NSColor.black.withAlphaComponent(0.85)
            t.letterSpacing = 1
            return t
        }()),
    ]

    private init() {
        theme = Theme()
        load()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(theme.fontName, forKey: "theme.fontName")
        d.set(Double(theme.currentLineFontSize), forKey: "theme.currentLineFontSize")
        d.set(Double(theme.nextLineFontSize), forKey: "theme.nextLineFontSize")
        d.set(Double(theme.letterSpacing), forKey: "theme.letterSpacing")
        d.set(theme.transitionStyle.rawValue, forKey: "theme.transitionStyle")
        d.set(theme.backgroundStyle.rawValue, forKey: "theme.backgroundStyle")
        d.set(Double(theme.backgroundCornerRadius), forKey: "theme.backgroundCornerRadius")
        d.set(theme.animationDuration, forKey: "theme.animationDuration")
        d.set(theme.overlayPosition.rawValue, forKey: "theme.overlayPosition")
        d.set(Double(theme.overlayWidth), forKey: "theme.overlayWidth")
        d.set(Double(theme.nextLineOpacity), forKey: "theme.nextLineOpacity")
        d.set(Double(theme.shadowBlurRadius), forKey: "theme.shadowBlurRadius")

        // Archive colors
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: theme.textColor, requiringSecureCoding: true) {
            d.set(data, forKey: "theme.textColor")
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: theme.backgroundColor, requiringSecureCoding: true) {
            d.set(data, forKey: "theme.backgroundColor")
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: theme.shadowColor, requiringSecureCoding: true) {
            d.set(data, forKey: "theme.shadowColor")
        }
    }

    private func load() {
        let d = UserDefaults.standard

        if let name = d.string(forKey: "theme.fontName") { theme.fontName = name }
        let cSize = d.double(forKey: "theme.currentLineFontSize")
        if cSize > 0 { theme.currentLineFontSize = CGFloat(cSize) }
        let nSize = d.double(forKey: "theme.nextLineFontSize")
        if nSize > 0 { theme.nextLineFontSize = CGFloat(nSize) }
        let ls = d.double(forKey: "theme.letterSpacing")
        if ls != 0 { theme.letterSpacing = CGFloat(ls) }

        if let raw = d.string(forKey: "theme.transitionStyle"),
           let v = TransitionStyle(rawValue: raw) { theme.transitionStyle = v }
        if let raw = d.string(forKey: "theme.backgroundStyle"),
           let v = BackgroundStyle(rawValue: raw) { theme.backgroundStyle = v }

        let cr = d.double(forKey: "theme.backgroundCornerRadius")
        if cr > 0 { theme.backgroundCornerRadius = CGFloat(cr) }
        let dur = d.double(forKey: "theme.animationDuration")
        if dur > 0 { theme.animationDuration = dur }
        if let raw = d.string(forKey: "theme.overlayPosition"),
           let v = OverlayPosition(rawValue: raw) { theme.overlayPosition = v }
        let ow = d.double(forKey: "theme.overlayWidth")
        if ow > 0 { theme.overlayWidth = CGFloat(ow) }
        let nlo = d.double(forKey: "theme.nextLineOpacity")
        if nlo > 0 { theme.nextLineOpacity = CGFloat(nlo) }
        let sbr = d.double(forKey: "theme.shadowBlurRadius")
        if sbr > 0 { theme.shadowBlurRadius = CGFloat(sbr) }

        // Unarchive colors
        if let data = d.data(forKey: "theme.textColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            theme.textColor = color
        }
        if let data = d.data(forKey: "theme.backgroundColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            theme.backgroundColor = color
        }
        if let data = d.data(forKey: "theme.shadowColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            theme.shadowColor = color
        }
    }

    func applyPreset(_ name: String) {
        if let preset = Self.presets.first(where: { $0.name == name }) {
            theme = preset.theme
        }
    }
}
