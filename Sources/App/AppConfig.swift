import Foundation

/// Centralized configuration for all persisted state.
///
/// Lookup order: TOML config file → UserDefaults → hardcoded default.
/// TOML file at ~/.config/yalyric/config.toml is optional (power users).
/// Settings UI writes to UserDefaults only. TOML overrides are read once at launch.
enum AppConfig {
    private static let d = UserDefaults.standard

    /// TOML overrides loaded once at launch. Section.key → value.
    /// e.g., "general.autoHideDelay" → 5.0
    private static let tomlOverrides: [String: Any] = loadTOML()

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/yalyric", isDirectory: true)
    static let configFile = configDir.appendingPathComponent("config.toml")

    private static func loadTOML() -> [String: Any] {
        guard let text = try? String(contentsOf: configFile, encoding: .utf8) else { return [:] }
        YalyricLog.info("[yalyric] Loaded config from \(configFile.path)")

        let parsed = TOMLParser.parse(text)
        // Flatten — use key name directly (matches UserDefaults keys).
        // TOML sections are for human readability only.
        var flat: [String: Any] = [:]
        for (_, pairs) in parsed {
            for (key, value) in pairs {
                flat[key] = value
            }
        }
        return flat
    }

    /// Generate a sample config with all current values
    static func exportConfig() -> String {
        let sections: [(String, String, [(String, Any)])] = [
            ("general", "General settings", [
                ("autoHideOnPause", get(General.autoHideOnPause)),
                ("autoHideDelay", get(General.autoHideDelay)),
                ("lyricsOffset", get(General.lyricsOffset)),
                ("lyricsLanguage", get(General.lyricsLanguage)),
                ("widgetLineCount", get(General.widgetLineCount)),
            ]),
            ("sources", "Lyrics provider settings", [
                ("spDCCookie", get(Sources.spDCCookie)),
                ("durationTolerance", get(Sources.durationTolerance)),
            ]),
            ("theme", "Appearance settings", [
                ("fontName", get(Theme.fontName)),
                ("currentLineFontSize", get(Theme.currentLineFontSize)),
                ("nextLineFontSize", get(Theme.nextLineFontSize)),
                ("letterSpacing", get(Theme.letterSpacing)),
                ("transitionStyle", get(Theme.transitionStyle)),
                ("backgroundStyle", get(Theme.backgroundStyle)),
                ("backgroundCornerRadius", get(Theme.backgroundCornerRadius)),
                ("backgroundOpacity", get(Theme.backgroundOpacity)),
                ("animationDuration", get(Theme.animationDuration)),
                ("overlayPosition", get(Theme.overlayPosition)),
                ("overlayWidth", get(Theme.overlayWidth)),
                ("nextLineOpacity", get(Theme.nextLineOpacity)),
                ("karaokeFillEnabled", get(Theme.karaokeFillEnabled)),
                ("fillEdgeWidth", get(Theme.fillEdgeWidth)),
                ("shadowBlurRadius", get(Theme.shadowBlurRadius)),
            ]),
            ("shortcuts", "Global keyboard shortcuts", [
                ("enabled", get(Shortcuts.enabled)),
                ("toggleOverlay", get(Shortcuts.toggleOverlay)),
                ("toggleAll", get(Shortcuts.toggleAll)),
                ("offsetPlus", get(Shortcuts.offsetPlus)),
                ("offsetMinus", get(Shortcuts.offsetMinus)),
                ("offsetReset", get(Shortcuts.offsetReset)),
            ]),
            ("overlay", "Overlay display behavior", [
                ("displayBehavior", get(Overlay.displayBehavior)),
                ("pinnedScreenIndex", get(Overlay.pinnedScreenIndex)),
            ]),
            ("widget", "Widget display behavior", [
                ("displayBehavior", get(Widget.displayBehavior)),
                ("pinnedScreenIndex", get(Widget.pinnedScreenIndex)),
            ]),
        ]

        var data: [String: [String: Any]] = [:]
        var comments: [String: String] = [:]
        for (section, comment, pairs) in sections {
            comments[section] = comment
            for (key, value) in pairs {
                data[section, default: [:]][key] = value
            }
        }
        return TOMLParser.serialize(data, comments: comments)
    }

    // MARK: - General

    enum General {
        static let hasLaunchedBefore = Key<Bool>("hasLaunchedBefore", default: false)
        static let enabledDisplayModes = Key<[String]>("enabledDisplayModes", default: ["Floating Overlay", "Menu Bar"])
        static let autoHideOnPause = Key<Bool>("autoHideOnPause", default: true)
        static let autoHideDelay = Key<Double>("autoHideDelay", default: 3.0)
        static let lyricsOffset = Key<Double>("lyricsOffset", default: 0)
        static let lyricsLanguage = Key<String>("lyricsLanguage", default: "Auto")
        static let widgetLineCount = Key<Int>("widgetLineCount", default: 5)
    }

    // MARK: - Sources

    enum Sources {
        static let providerOrder = Key<[String]>("providerOrder", default: ["lrclib", "spotify", "musixmatch", "netease"])
        static let spDCCookie = Key<String>("spDCCookie", default: "")
        static let durationTolerance = Key<Double>("durationTolerance", default: 30.0)
        static let musixmatchToken = Key<String>("musixmatch.token", default: "")
        static let musixmatchTokenExpiry = Key<Double>("musixmatch.tokenExpiry", default: 0)
    }

    // MARK: - Theme

    enum Theme {
        static let saved = Key<Bool>("theme.saved", default: false)
        static let fontName = Key<String>("theme.fontName", default: "")
        static let currentLineFontSize = Key<Double>("theme.currentLineFontSize", default: 24)
        static let nextLineFontSize = Key<Double>("theme.nextLineFontSize", default: 16)
        static let fontWeight = Key<Double>("theme.fontWeight", default: 0.0)
        static let letterSpacing = Key<Double>("theme.letterSpacing", default: 0)
        static let transitionStyle = Key<String>("theme.transitionStyle", default: "Slide Up")
        static let backgroundStyle = Key<String>("theme.backgroundStyle", default: "None (Transparent)")
        static let backgroundCornerRadius = Key<Double>("theme.backgroundCornerRadius", default: 12)
        static let backgroundOpacity = Key<Double>("theme.backgroundOpacity", default: 0.5)
        static let animationDuration = Key<Double>("theme.animationDuration", default: 0.5)
        static let overlayPosition = Key<String>("theme.overlayPosition", default: "Bottom Center")
        static let overlayWidth = Key<Double>("theme.overlayWidth", default: 800)
        static let nextLineOpacity = Key<Double>("theme.nextLineOpacity", default: 0.5)
        static let karaokeFillEnabled = Key<Bool>("theme.karaokeFillEnabled", default: false)
        static let fillEdgeWidth = Key<Double>("theme.fillEdgeWidth", default: 0.06)
        static let shadowBlurRadius = Key<Double>("theme.shadowBlurRadius", default: 4)
        static let shadowOffsetX = Key<Double>("theme.shadowOffsetX", default: 0)
        static let shadowOffsetY = Key<Double>("theme.shadowOffsetY", default: -1)
        // NSColor keys (stored as Data via NSKeyedArchiver, not in TOML)
        static let textColor = "theme.textColor"
        static let backgroundColor = "theme.backgroundColor"
        static let shadowColor = "theme.shadowColor"
    }

    // MARK: - Overlay Position

    enum Overlay {
        static let hasCustomPosition = Key<Bool>("overlay.hasCustomPosition", default: false)
        static let customCenterX = Key<Double>("overlay.customCenterX", default: 0)
        static let customY = Key<Double>("overlay.customY", default: 0)
        static let displayBehavior = Key<String>("overlay.displayBehavior", default: "Follow Mouse")
        static let pinnedScreenIndex = Key<Int>("overlay.pinnedScreenIndex", default: 0)
    }

    // MARK: - Widget Position

    enum Widget {
        static let hasCustomPosition = Key<Bool>("widget.hasCustomPosition", default: false)
        static let customCenterX = Key<Double>("widget.customCenterX", default: 0)
        static let customY = Key<Double>("widget.customY", default: 0)
        static let displayBehavior = Key<String>("widget.displayBehavior", default: "Follow Mouse")
        static let pinnedScreenIndex = Key<Int>("widget.pinnedScreenIndex", default: 0)
    }

    // MARK: - Shortcuts

    enum Shortcuts {
        static let enabled = Key<Bool>("shortcuts.enabled", default: true)
        static let toggleOverlay = Key<String>("shortcuts.toggleOverlay", default: "ctrl+opt+l")
        static let toggleAll = Key<String>("shortcuts.toggleAll", default: "ctrl+opt+h")
        static let offsetPlus = Key<String>("shortcuts.offsetPlus", default: "ctrl+opt+right")
        static let offsetMinus = Key<String>("shortcuts.offsetMinus", default: "ctrl+opt+left")
        static let offsetReset = Key<String>("shortcuts.offsetReset", default: "ctrl+opt+0")
    }

    // MARK: - Typed Key

    struct Key<T> {
        let name: String
        let defaultValue: T

        init(_ name: String, `default`: T) {
            self.name = name
            self.defaultValue = `default`
        }
    }
}

// MARK: - Typed Read/Write (TOML override → UserDefaults → default)

extension AppConfig {
    static func get(_ key: Key<Bool>) -> Bool {
        if let v = tomlOverrides[key.name] as? Bool { return v }
        return d.object(forKey: key.name) != nil ? d.bool(forKey: key.name) : key.defaultValue
    }
    static func get(_ key: Key<Int>) -> Int {
        if let v = tomlOverrides[key.name] as? Int { return v }
        return d.object(forKey: key.name) != nil ? d.integer(forKey: key.name) : key.defaultValue
    }
    static func get(_ key: Key<Double>) -> Double {
        if let v = tomlOverrides[key.name] as? Double { return v }
        if let v = tomlOverrides[key.name] as? Int { return Double(v) }
        return d.object(forKey: key.name) != nil ? d.double(forKey: key.name) : key.defaultValue
    }
    static func get(_ key: Key<String>) -> String {
        if let v = tomlOverrides[key.name] as? String { return v }
        return d.string(forKey: key.name) ?? key.defaultValue
    }
    static func get(_ key: Key<[String]>) -> [String] {
        d.stringArray(forKey: key.name) ?? key.defaultValue
    }

    static func set(_ key: Key<Bool>, _ value: Bool) { d.set(value, forKey: key.name) }
    static func set(_ key: Key<Int>, _ value: Int) { d.set(value, forKey: key.name) }
    static func set(_ key: Key<Double>, _ value: Double) { d.set(value, forKey: key.name) }
    static func set(_ key: Key<String>, _ value: String) { d.set(value, forKey: key.name) }
    static func set(_ key: Key<[String]>, _ value: [String]) { d.set(value, forKey: key.name) }

    static func remove(_ key: Key<Bool>) { d.removeObject(forKey: key.name) }
    static func remove(_ key: Key<Double>) { d.removeObject(forKey: key.name) }
    static func remove(_ key: Key<String>) { d.removeObject(forKey: key.name) }
}
