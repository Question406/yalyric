import AppKit
import SwiftUI
import Combine

// MARK: - Data Models

enum DisplayMode: String, CaseIterable {
    case overlay = "Floating Overlay"
    case desktop = "Desktop Widget"
    case menuBar = "Menu Bar"
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var enabledDisplayModes: Set<DisplayMode> {
        didSet {
            let raw = enabledDisplayModes.map { $0.rawValue }
            UserDefaults.standard.set(raw, forKey: "enabledDisplayModes")
        }
    }

    @Published var spDCCookie: String {
        didSet { UserDefaults.standard.set(spDCCookie, forKey: "spDCCookie") }
    }

    @Published var lyricsLanguage: LyricsLanguagePreference {
        didSet { UserDefaults.standard.set(lyricsLanguage.rawValue, forKey: "lyricsLanguage") }
    }

    @Published var autoHideOnPause: Bool {
        didSet { UserDefaults.standard.set(autoHideOnPause, forKey: "autoHideOnPause") }
    }

    @Published var autoHideDelay: TimeInterval {
        didSet { UserDefaults.standard.set(autoHideDelay, forKey: "autoHideDelay") }
    }

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: "enabledDisplayModes") {
            enabledDisplayModes = Set(saved.compactMap { DisplayMode(rawValue: $0) })
        } else {
            enabledDisplayModes = [.overlay, .menuBar]
        }

        spDCCookie = UserDefaults.standard.string(forKey: "spDCCookie") ?? ""

        if let savedLang = UserDefaults.standard.string(forKey: "lyricsLanguage"),
           let lang = LyricsLanguagePreference(rawValue: savedLang) {
            lyricsLanguage = lang
        } else {
            lyricsLanguage = .auto
        }

        autoHideOnPause = UserDefaults.standard.object(forKey: "autoHideOnPause") as? Bool ?? true
        let savedDelay = UserDefaults.standard.double(forKey: "autoHideDelay")
        autoHideDelay = savedDelay > 0 ? savedDelay : 3.0
    }
}

// MARK: - SwiftUI Settings View

struct SettingsContentView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var themeManager = ThemeManager.shared

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }
            AppearanceTab(themeManager: themeManager)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            SourcesTab(settings: settings)
                .tabItem { Label("Sources", systemImage: "music.note.list") }
        }
        .frame(width: 500, height: 460)
        .padding(8)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Display Modes") {
                ForEach(DisplayMode.allCases, id: \.rawValue) { mode in
                    Toggle(mode.rawValue, isOn: Binding(
                        get: { settings.enabledDisplayModes.contains(mode) },
                        set: { enabled in
                            if enabled { settings.enabledDisplayModes.insert(mode) }
                            else { settings.enabledDisplayModes.remove(mode) }
                            NotificationCenter.default.post(name: .displayModesChanged, object: nil)
                        }
                    ))
                }
            }

            Section("Behavior") {
                Toggle("Auto-hide overlay when paused", isOn: $settings.autoHideOnPause)
                if settings.autoHideOnPause {
                    HStack {
                        Text("Hide after")
                        Picker("", selection: $settings.autoHideDelay) {
                            Text("Immediately").tag(0.0 as TimeInterval)
                            Text("3 seconds").tag(3.0 as TimeInterval)
                            Text("5 seconds").tag(5.0 as TimeInterval)
                            Text("10 seconds").tag(10.0 as TimeInterval)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
            }

            Section("Lyrics Language") {
                Picker("Preferred language", selection: $settings.lyricsLanguage) {
                    ForEach(LyricsLanguagePreference.allCases, id: \.rawValue) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                Text("\"Auto\" detects the song's language and filters mismatched lyrics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance Tab

struct AppearanceTab: View {
    @ObservedObject var themeManager: ThemeManager

    @State private var textColorSwiftUI: Color = .white
    @State private var bgColorSwiftUI: Color = Color(nsColor: NSColor.black.withAlphaComponent(0.5))

    var body: some View {
        Form {
            Section("Theme Presets") {
                HStack(spacing: 8) {
                    ForEach(ThemeManager.presets, id: \.name) { preset in
                        Button(preset.name) {
                            themeManager.applyPreset(preset.name)
                            syncColorsFromTheme()
                            NotificationCenter.default.post(name: .displayModesChanged, object: nil)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section("Typography") {
                HStack {
                    Text("Font")
                    Spacer()
                    Picker("", selection: $themeManager.theme.fontName) {
                        Text("System (SF Pro)").tag("")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Helvetica Neue").tag("Helvetica Neue")
                        Text("Georgia").tag("Georgia")
                        Text("Futura").tag("Futura Medium")
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                LabeledSlider(
                    label: "Current line size",
                    value: $themeManager.theme.currentLineFontSize,
                    range: 12...48,
                    format: "%.0fpt"
                )
                LabeledSlider(
                    label: "Next line size",
                    value: $themeManager.theme.nextLineFontSize,
                    range: 10...36,
                    format: "%.0fpt"
                )
                LabeledSlider(
                    label: "Letter spacing",
                    value: $themeManager.theme.letterSpacing,
                    range: -2...8,
                    format: "%.1f"
                )
            }

            Section("Colors") {
                ColorPicker("Text color", selection: $textColorSwiftUI, supportsOpacity: false)
                    .onChange(of: textColorSwiftUI) { newValue in
                        themeManager.theme.textColor = NSColor(newValue)
                    }
                LabeledSlider(
                    label: "Next line opacity",
                    value: $themeManager.theme.nextLineOpacity,
                    range: 0.1...1.0,
                    format: "%.0f%%",
                    displayMultiplier: 100
                )
                LabeledSlider(
                    label: "Shadow blur",
                    value: $themeManager.theme.shadowBlurRadius,
                    range: 0...20,
                    format: "%.0f"
                )
            }

            Section("Background") {
                Picker("Style", selection: $themeManager.theme.backgroundStyle) {
                    ForEach(BackgroundStyle.allCases, id: \.rawValue) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                if themeManager.theme.backgroundStyle != .none {
                    ColorPicker("Background color", selection: $bgColorSwiftUI, supportsOpacity: true)
                        .onChange(of: bgColorSwiftUI) { newValue in
                            themeManager.theme.backgroundColor = NSColor(newValue)
                        }
                    if themeManager.theme.backgroundStyle == .pill {
                        LabeledSlider(
                            label: "Corner radius",
                            value: $themeManager.theme.backgroundCornerRadius,
                            range: 0...24,
                            format: "%.0f"
                        )
                    }
                }
            }

            Section("Animation") {
                Picker("Transition", selection: $themeManager.theme.transitionStyle) {
                    ForEach(TransitionStyle.allCases, id: \.rawValue) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                if themeManager.theme.transitionStyle != .none {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Slider(value: $themeManager.theme.animationDuration, in: 0.1...1.0)
                            .frame(width: 180)
                        Text(String(format: "%.1fs", themeManager.theme.animationDuration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Position") {
                Picker("Overlay position", selection: $themeManager.theme.overlayPosition) {
                    ForEach(OverlayPosition.allCases, id: \.rawValue) { pos in
                        Text(pos.rawValue).tag(pos)
                    }
                }
                LabeledSlider(
                    label: "Overlay width",
                    value: $themeManager.theme.overlayWidth,
                    range: 400...1600,
                    format: "%.0f"
                )
            }
        }
        .formStyle(.grouped)
        .onAppear { syncColorsFromTheme() }
        .onChange(of: themeManager.theme) { _ in
            syncColorsFromTheme()
            NotificationCenter.default.post(name: .displayModesChanged, object: nil)
        }
    }

    private func syncColorsFromTheme() {
        textColorSwiftUI = Color(nsColor: themeManager.theme.textColor)
        bgColorSwiftUI = Color(nsColor: themeManager.theme.backgroundColor)
    }
}

// MARK: - Sources Tab

struct SourcesTab: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Lyrics Providers") {
                Text("Providers are tried in order. The first to return synced lyrics wins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: "1.circle.fill")
                    Text("LRCLIB")
                    Spacer()
                    Text("Free, no auth")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: "2.circle.fill")
                    Text("Spotify Internal")
                    Spacer()
                    Text("Requires SP_DC cookie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: "3.circle.fill")
                    Text("Musixmatch")
                    Spacer()
                    Text("Auto-token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: "4.circle.fill")
                    Text("NetEase Cloud Music")
                    Spacer()
                    Text("Good for CJK")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Spotify SP_DC Cookie") {
                SecureField("Paste your sp_dc cookie here", text: $settings.spDCCookie)
                Text("Get from Spotify Web Player → DevTools → Application → Cookies → sp_dc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Helpers

struct LabeledSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: String
    var displayMultiplier: CGFloat = 1

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Slider(value: $value, in: range)
                .frame(width: 180)
            Text(String(format: format, value * displayMultiplier))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

// MARK: - Window Controller

class SettingsWindowController: NSWindowController {
    convenience init() {
        let settingsView = SettingsContentView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "yalyric Settings"
        window.styleMask = [.titled, .closable]
        window.center()

        self.init(window: window)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let displayModesChanged = Notification.Name("displayModesChanged")
}
