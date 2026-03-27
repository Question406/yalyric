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

    @Published var providerOrder: [String] {
        didSet { UserDefaults.standard.set(providerOrder, forKey: "providerOrder") }
    }

    @Published var autoHideOnPause: Bool {
        didSet { UserDefaults.standard.set(autoHideOnPause, forKey: "autoHideOnPause") }
    }

    @Published var autoHideDelay: TimeInterval {
        didSet { UserDefaults.standard.set(autoHideDelay, forKey: "autoHideDelay") }
    }

    @Published var lyricsOffset: TimeInterval {
        didSet { UserDefaults.standard.set(lyricsOffset, forKey: "lyricsOffset") }
    }

    @Published var durationTolerance: TimeInterval {
        didSet { UserDefaults.standard.set(durationTolerance, forKey: "durationTolerance") }
    }

    @Published var widgetLineCount: Int {
        didSet {
            UserDefaults.standard.set(widgetLineCount, forKey: "widgetLineCount")
            NotificationCenter.default.post(name: .displayModesChanged, object: nil)
        }
    }

    static let defaultProviderOrder = ["lrclib", "spotify", "musixmatch", "netease"]

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

        if let saved = UserDefaults.standard.stringArray(forKey: "providerOrder"), !saved.isEmpty {
            providerOrder = saved
        } else {
            providerOrder = Self.defaultProviderOrder
        }

        autoHideOnPause = UserDefaults.standard.object(forKey: "autoHideOnPause") as? Bool ?? true
        let savedDelay = UserDefaults.standard.double(forKey: "autoHideDelay")
        autoHideDelay = savedDelay > 0 ? savedDelay : 3.0
        lyricsOffset = UserDefaults.standard.double(forKey: "lyricsOffset")
        let savedTolerance = UserDefaults.standard.double(forKey: "durationTolerance")
        durationTolerance = savedTolerance > 0 ? savedTolerance : 30.0
        let savedLines = UserDefaults.standard.integer(forKey: "widgetLineCount")
        widgetLineCount = savedLines > 0 ? savedLines : 5
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

            Section("Desktop Widget") {
                Picker("Visible lines", selection: $settings.widgetLineCount) {
                    Text("3").tag(3)
                    Text("5").tag(5)
                    Text("7").tag(7)
                    Text("9").tag(9)
                }
            }

            Section("Lyrics Timing") {
                HStack {
                    Text("Offset")
                    Spacer()
                    Button("-0.5s") { settings.lyricsOffset -= 0.5 }
                        .controlSize(.small)
                    Text(String(format: "%+.1fs", settings.lyricsOffset))
                        .frame(width: 50)
                        .multilineTextAlignment(.center)
                        .font(.system(.body, design: .monospaced))
                    Button("+0.5s") { settings.lyricsOffset += 0.5 }
                        .controlSize(.small)
                    Button("Reset") { settings.lyricsOffset = 0 }
                        .controlSize(.small)
                }
                Text("Positive = lyrics appear earlier, negative = later")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                if themeManager.theme.backgroundStyle == .solidPill {
                    ColorPicker("Background color", selection: $bgColorSwiftUI, supportsOpacity: true)
                        .onChange(of: bgColorSwiftUI) { newValue in
                            themeManager.theme.backgroundColor = NSColor(newValue)
                        }
                }
                if themeManager.theme.backgroundStyle != .none {
                    LabeledSlider(
                        label: "Opacity",
                        value: $themeManager.theme.backgroundOpacity,
                        range: 0.0...1.0,
                        format: "%.0f%%",
                        displayMultiplier: 100
                    )
                }
                if themeManager.theme.backgroundStyle == .frostedPill || themeManager.theme.backgroundStyle == .solidPill {
                    LabeledSlider(
                        label: "Corner radius",
                        value: $themeManager.theme.backgroundCornerRadius,
                        range: 0...24,
                        format: "%.0f"
                    )
                }
            }

            Section("Karaoke Fill") {
                Toggle("Enable line fill effect", isOn: $themeManager.theme.karaokeFillEnabled)
                if themeManager.theme.karaokeFillEnabled {
                    LabeledSlider(
                        label: "Edge softness",
                        value: $themeManager.theme.fillEdgeWidth,
                        range: 0.02...0.20,
                        format: "%.0f%%",
                        displayMultiplier: 100
                    )
                    Text("A gradient sweeps across the current line in sync with the song")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    ForEach(OverlayPosition.allCases.filter { $0 != .custom }, id: \.rawValue) { pos in
                        Text(pos.rawValue).tag(pos)
                    }
                    if AppConfig.get(AppConfig.Overlay.hasCustomPosition) {
                        Text("Custom").tag(OverlayPosition.custom)
                    }
                }
                .onChange(of: themeManager.theme.overlayPosition) { newValue in
                    if newValue != .custom {
                        AppConfig.set(AppConfig.Overlay.hasCustomPosition, false)
                        AppConfig.set(AppConfig.Overlay.customCenterX, 0)
                        AppConfig.set(AppConfig.Overlay.customY, 0)
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

struct ProviderInfo {
    let id: String
    let name: String
    let detail: String

    static let all: [String: ProviderInfo] = [
        "lrclib": ProviderInfo(id: "lrclib", name: "LRCLIB", detail: "Free, no auth"),
        "spotify": ProviderInfo(id: "spotify", name: "Spotify Internal", detail: "Requires SP_DC cookie"),
        "musixmatch": ProviderInfo(id: "musixmatch", name: "Musixmatch", detail: "Auto-token"),
        "netease": ProviderInfo(id: "netease", name: "NetEase Cloud Music", detail: "Good for CJK"),
    ]
}

struct SourcesTab: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            Section {
                Text("Drag to reorder. Providers are tried top-to-bottom; the first to return synced lyrics wins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List {
                    ForEach(settings.providerOrder, id: \.self) { id in
                        if let info = ProviderInfo.all[id] {
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
                                Text(info.name)
                                Spacer()
                                Text(info.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onMove { from, to in
                        settings.providerOrder.move(fromOffsets: from, toOffset: to)
                    }
                }
                .frame(height: 140)

                Button("Reset to Default Order") {
                    settings.providerOrder = SettingsManager.defaultProviderOrder
                }
                .controlSize(.small)
            } header: {
                Text("Lyrics Providers")
            }

            Section("Duration Matching") {
                HStack {
                    Text("Tolerance")
                    Spacer()
                    Slider(value: $settings.durationTolerance, in: 5...60, step: 5)
                        .frame(width: 180)
                    Text(String(format: "%.0fs", settings.durationTolerance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                Text("How much duration mismatch to allow between Spotify and lyrics databases")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
