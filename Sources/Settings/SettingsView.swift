import AppKit

enum DisplayMode: String, CaseIterable {
    case overlay = "Floating Overlay"
    case desktop = "Desktop Widget"
    case menuBar = "Menu Bar"
    case sidebar = "Sidebar Panel"
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var enabledDisplayModes: Set<DisplayMode> {
        didSet {
            let raw = enabledDisplayModes.map { $0.rawValue }
            UserDefaults.standard.set(raw, forKey: "enabledDisplayModes")
        }
    }

    @Published var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: "fontSize") }
    }

    @Published var spDCCookie: String {
        didSet { UserDefaults.standard.set(spDCCookie, forKey: "spDCCookie") }
    }

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: "enabledDisplayModes") {
            enabledDisplayModes = Set(saved.compactMap { DisplayMode(rawValue: $0) })
        } else {
            enabledDisplayModes = [.overlay, .menuBar]
        }

        let savedSize = UserDefaults.standard.double(forKey: "fontSize")
        fontSize = savedSize > 0 ? CGFloat(savedSize) : 24

        spDCCookie = UserDefaults.standard.string(forKey: "spDCCookie") ?? ""
    }
}

class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "yalyric Settings"
        window.center()

        self.init(window: window)
        setupContent()
    }

    private func setupContent() {
        guard let window = window else { return }
        let settings = SettingsManager.shared

        let container = NSView(frame: window.contentView!.bounds)
        container.autoresizingMask = [.width, .height]

        var yOffset: CGFloat = 300

        // Section: Display Modes
        let modeTitle = makeLabel("Display Modes", bold: true)
        modeTitle.frame.origin = NSPoint(x: 20, y: yOffset)
        container.addSubview(modeTitle)
        yOffset -= 30

        for mode in DisplayMode.allCases {
            let checkbox = NSButton(checkboxWithTitle: mode.rawValue, target: nil, action: nil)
            checkbox.state = settings.enabledDisplayModes.contains(mode) ? .on : .off
            checkbox.frame.origin = NSPoint(x: 30, y: yOffset)
            checkbox.tag = DisplayMode.allCases.firstIndex(of: mode)!
            checkbox.target = self
            checkbox.action = #selector(toggleDisplayMode(_:))
            container.addSubview(checkbox)
            yOffset -= 26
        }

        yOffset -= 10

        // Section: Spotify SP_DC Cookie
        let cookieTitle = makeLabel("Spotify SP_DC Cookie (for Spotify lyrics source)", bold: true)
        cookieTitle.frame.origin = NSPoint(x: 20, y: yOffset)
        container.addSubview(cookieTitle)
        yOffset -= 28

        let cookieField = NSTextField(frame: NSRect(x: 30, y: yOffset, width: 380, height: 24))
        cookieField.stringValue = settings.spDCCookie
        cookieField.placeholderString = "Paste your sp_dc cookie here"
        cookieField.target = self
        cookieField.action = #selector(cookieChanged(_:))
        container.addSubview(cookieField)
        yOffset -= 22

        let cookieHint = makeLabel("Get from Spotify Web Player cookies in browser DevTools", bold: false)
        cookieHint.font = NSFont.systemFont(ofSize: 11)
        cookieHint.textColor = .secondaryLabelColor
        cookieHint.frame.origin = NSPoint(x: 30, y: yOffset)
        container.addSubview(cookieHint)
        yOffset -= 30

        // Section: Font Size
        let fontTitle = makeLabel("Font Size: \(Int(settings.fontSize))pt", bold: true)
        fontTitle.frame.origin = NSPoint(x: 20, y: yOffset)
        fontTitle.tag = 999
        container.addSubview(fontTitle)
        yOffset -= 28

        let slider = NSSlider(value: Double(settings.fontSize), minValue: 12, maxValue: 48, target: self, action: #selector(fontSizeChanged(_:)))
        slider.frame = NSRect(x: 30, y: yOffset, width: 380, height: 24)
        container.addSubview(slider)

        window.contentView = container
    }

    private func makeLabel(_ text: String, bold: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.systemFont(ofSize: 13, weight: .semibold) : NSFont.systemFont(ofSize: 13)
        label.sizeToFit()
        return label
    }

    @objc private func toggleDisplayMode(_ sender: NSButton) {
        let mode = DisplayMode.allCases[sender.tag]
        if sender.state == .on {
            SettingsManager.shared.enabledDisplayModes.insert(mode)
        } else {
            SettingsManager.shared.enabledDisplayModes.remove(mode)
        }
        NotificationCenter.default.post(name: .displayModesChanged, object: nil)
    }

    @objc private func cookieChanged(_ sender: NSTextField) {
        SettingsManager.shared.spDCCookie = sender.stringValue
    }

    @objc private func fontSizeChanged(_ sender: NSSlider) {
        SettingsManager.shared.fontSize = CGFloat(sender.doubleValue)
        // Update the label
        if let label = window?.contentView?.viewWithTag(999) as? NSTextField {
            label.stringValue = "Font Size: \(Int(sender.doubleValue))pt"
        }
        NotificationCenter.default.post(name: .displayModesChanged, object: nil)
    }
}

extension Notification.Name {
    static let displayModesChanged = Notification.Name("displayModesChanged")
}
