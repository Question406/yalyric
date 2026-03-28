import Carbon.HIToolbox

/// Parsed shortcut: Carbon modifier flags + virtual key code.
struct ParsedShortcut {
    let modifiers: UInt32
    let keyCode: UInt32
}

/// Parses human-readable shortcut strings like "ctrl+opt+l" into Carbon key codes.
enum ShortcutParser {
    // Carbon modifier flags
    static let controlKey: UInt32 = UInt32(Carbon.controlKey)
    static let optionKey: UInt32 = UInt32(Carbon.optionKey)
    static let cmdKey: UInt32 = UInt32(Carbon.cmdKey)
    static let shiftKey: UInt32 = UInt32(Carbon.shiftKey)

    private static let modifierMap: [String: UInt32] = [
        "ctrl": controlKey,
        "opt": optionKey,
        "cmd": cmdKey,
        "shift": shiftKey,
    ]

    private static let keyCodeMap: [String: UInt32] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
        "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
        "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
        "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
        "z": 0x06,
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        "left": 0x7B, "right": 0x7C, "up": 0x7E, "down": 0x7D,
        "space": 0x31, "tab": 0x30, "return": 0x24, "escape": 0x35,
        "delete": 0x33, "f1": 0x7A, "f2": 0x78, "f3": 0x63,
        "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
    ]

    private static let modifierSymbols: [(String, String)] = [
        ("ctrl", "⌃"), ("opt", "⌥"), ("shift", "⇧"), ("cmd", "⌘"),
    ]

    private static let keySymbols: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "space": "Space", "tab": "⇥", "return": "↩", "escape": "⎋",
        "delete": "⌫",
    ]

    /// Parse "ctrl+opt+l" → ParsedShortcut(modifiers, keyCode), or nil on failure.
    static func parse(_ shortcut: String) -> ParsedShortcut? {
        let parts = shortcut.lowercased().split(separator: "+").map(String.init)
        guard parts.count >= 2 else { return nil }

        var modifiers: UInt32 = 0
        var keyPart: String?

        for part in parts {
            if let mod = modifierMap[part] {
                modifiers |= mod
            } else {
                keyPart = part
            }
        }

        guard modifiers != 0, let key = keyPart, let keyCode = keyCodeMap[key] else {
            return nil
        }

        return ParsedShortcut(modifiers: modifiers, keyCode: keyCode)
    }

    /// Convert "ctrl+opt+l" → "⌃⌥L" for display in UI.
    static func displayString(_ shortcut: String) -> String {
        let parts = shortcut.lowercased().split(separator: "+").map(String.init)
        var result = ""

        // Modifiers in standard macOS order: ⌃⌥⇧⌘
        for (name, symbol) in modifierSymbols {
            if parts.contains(name) {
                result += symbol
            }
        }

        // Key part (last non-modifier)
        if let key = parts.last, modifierMap[key] == nil {
            if let symbol = keySymbols[key] {
                result += symbol
            } else {
                result += key.uppercased()
            }
        }

        return result
    }
}

/// Global hotkey manager using Carbon RegisterEventHotKey.
/// No accessibility permission required.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    // Actions — set by AppDelegate
    var onToggleOverlay: (() -> Void)?
    var onToggleAll: (() -> Void)?
    var onOffsetPlus: (() -> Void)?
    var onOffsetMinus: (() -> Void)?
    var onOffsetReset: (() -> Void)?

    private var hotkeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    // Hotkey IDs — must match the switch in the handler
    private enum HotkeyID: UInt32 {
        case toggleOverlay = 1
        case toggleAll = 2
        case offsetPlus = 3
        case offsetMinus = 4
        case offsetReset = 5
    }

    private init() {}

    func registerAll() {
        unregisterAll()

        guard AppConfig.get(AppConfig.Shortcuts.enabled) else {
            YalyricLog.info("[yalyric] Global shortcuts disabled")
            return
        }

        // Install a single Carbon event handler for all hotkeys
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerResult = InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &eventType, nil, &eventHandlerRef)
        guard handlerResult == noErr else {
            YalyricLog.error("[yalyric] Failed to install hotkey event handler: \(handlerResult)")
            return
        }

        // Register each shortcut
        let bindings: [(HotkeyID, AppConfig.Key<String>)] = [
            (.toggleOverlay, AppConfig.Shortcuts.toggleOverlay),
            (.toggleAll, AppConfig.Shortcuts.toggleAll),
            (.offsetPlus, AppConfig.Shortcuts.offsetPlus),
            (.offsetMinus, AppConfig.Shortcuts.offsetMinus),
            (.offsetReset, AppConfig.Shortcuts.offsetReset),
        ]

        for (id, configKey) in bindings {
            let shortcutStr = AppConfig.get(configKey)
            guard let parsed = ShortcutParser.parse(shortcutStr) else {
                YalyricLog.error("[yalyric] Invalid shortcut: \(shortcutStr)")
                continue
            }

            let hotkeyID = EventHotKeyID(signature: OSType(0x594C5243), id: id.rawValue) // "YLRC"
            var hotkeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(parsed.keyCode, parsed.modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
            if status == noErr, let ref = hotkeyRef {
                hotkeyRefs.append(ref)
                let display = ShortcutParser.displayString(shortcutStr)
                YalyricLog.info("[yalyric] Registered hotkey: \(display)")
            } else {
                YalyricLog.error("[yalyric] Failed to register hotkey \(shortcutStr): \(status)")
            }
        }
    }

    func unregisterAll() {
        for ref in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()

        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    /// Called from the C callback on the main thread.
    func handleHotkey(id: UInt32) {
        guard let hotkeyID = HotkeyID(rawValue: id) else { return }
        switch hotkeyID {
        case .toggleOverlay: onToggleOverlay?()
        case .toggleAll: onToggleAll?()
        case .offsetPlus: onOffsetPlus?()
        case .offsetMinus: onOffsetMinus?()
        case .offsetReset: onOffsetReset?()
        }
    }
}

/// C function pointer for Carbon event handler.
/// Cannot capture context — uses the global HotkeyManager.shared singleton.
private func hotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
    guard status == noErr else { return status }
    MainActor.assumeIsolated {
        HotkeyManager.shared.handleHotkey(id: hotkeyID.id)
    }
    return noErr
}
