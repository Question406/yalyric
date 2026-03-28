# Global Keyboard Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 5 global keyboard shortcuts (toggle overlay, toggle all, offset +/-, reset offset) using Carbon Hot Keys with no external dependencies.

**Architecture:** A `HotkeyManager` singleton wraps the Carbon `RegisterEventHotKey` API. A `ShortcutParser` converts human-readable strings like `"ctrl+opt+l"` into Carbon key codes and modifier flags. AppDelegate wires action closures and manages toggle state. Settings UI adds a Shortcuts tab.

**Tech Stack:** Swift, Carbon.HIToolbox (RegisterEventHotKey), AppKit, SwiftUI

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Sources/App/HotkeyManager.swift` | Create | Carbon hotkey registration, event handling, action dispatch |
| `Sources/App/AppConfig.swift` | Modify | Add `Shortcuts` config keys |
| `Sources/App/AppDelegate.swift` | Modify | Wire hotkey actions, add toggle/nudge/reset methods |
| `Sources/Settings/SettingsView.swift` | Modify | Add Shortcuts tab |
| `Tests/HotkeyTests.swift` | Create | Test shortcut string parsing |

---

### Task 1: Shortcut String Parser and Tests

**Files:**
- Create: `Sources/App/HotkeyManager.swift` (parser portion only)
- Create: `Tests/HotkeyTests.swift`

- [ ] **Step 1: Write the failing tests for shortcut parsing**

Create `Tests/HotkeyTests.swift`:

```swift
import XCTest
@testable import yalyricLib

final class HotkeyTests: XCTestCase {

    // MARK: - Modifier Parsing

    func testParseCtrlOpt() {
        let result = ShortcutParser.parse("ctrl+opt+l")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.modifiers, ShortcutParser.controlKey | ShortcutParser.optionKey)
    }

    func testParseCmdShift() {
        let result = ShortcutParser.parse("cmd+shift+a")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.modifiers, ShortcutParser.cmdKey | ShortcutParser.shiftKey)
    }

    func testParseAllModifiers() {
        let result = ShortcutParser.parse("ctrl+opt+cmd+shift+x")
        XCTAssertNotNil(result)
        let expected = ShortcutParser.controlKey | ShortcutParser.optionKey | ShortcutParser.cmdKey | ShortcutParser.shiftKey
        XCTAssertEqual(result!.modifiers, expected)
    }

    // MARK: - Key Code Parsing

    func testParseLetterKey() {
        let result = ShortcutParser.parse("ctrl+opt+l")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x25) // kVK_ANSI_L
    }

    func testParseNumberKey() {
        let result = ShortcutParser.parse("ctrl+opt+0")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x1D) // kVK_ANSI_0
    }

    func testParseArrowRight() {
        let result = ShortcutParser.parse("ctrl+opt+right")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x7C) // kVK_RightArrow
    }

    func testParseArrowLeft() {
        let result = ShortcutParser.parse("ctrl+opt+left")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x7B) // kVK_LeftArrow
    }

    func testParseHKey() {
        let result = ShortcutParser.parse("ctrl+opt+h")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x04) // kVK_ANSI_H
    }

    // MARK: - Edge Cases

    func testParseEmptyString() {
        let result = ShortcutParser.parse("")
        XCTAssertNil(result)
    }

    func testParseNoModifiers() {
        let result = ShortcutParser.parse("l")
        XCTAssertNil(result)
    }

    func testParseUnknownKey() {
        let result = ShortcutParser.parse("ctrl+opt+banana")
        XCTAssertNil(result)
    }

    func testParseCaseInsensitive() {
        let result = ShortcutParser.parse("Ctrl+Opt+L")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keyCode, 0x25) // kVK_ANSI_L
    }

    // MARK: - Display String

    func testDisplayString() {
        XCTAssertEqual(ShortcutParser.displayString("ctrl+opt+l"), "⌃⌥L")
        XCTAssertEqual(ShortcutParser.displayString("ctrl+opt+right"), "⌃⌥→")
        XCTAssertEqual(ShortcutParser.displayString("ctrl+opt+0"), "⌃⌥0")
        XCTAssertEqual(ShortcutParser.displayString("cmd+shift+a"), "⇧⌘A")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HotkeyTests 2>&1 | tail -5`
Expected: Compilation error — `ShortcutParser` does not exist.

- [ ] **Step 3: Implement ShortcutParser**

Create `Sources/App/HotkeyManager.swift` with the parser (hotkey registration comes in Task 2):

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HotkeyTests 2>&1 | tail -5`
Expected: All 13 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/HotkeyManager.swift Tests/HotkeyTests.swift
git commit -m "feat: add ShortcutParser for global hotkey string parsing"
```

---

### Task 2: Carbon Hot Key Registration in HotkeyManager

**Files:**
- Modify: `Sources/App/HotkeyManager.swift` (add HotkeyManager class)

- [ ] **Step 1: Add HotkeyManager class to HotkeyManager.swift**

Append to the existing `Sources/App/HotkeyManager.swift` after the `ShortcutParser` enum:

```swift
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

            var hotkeyID = EventHotKeyID(signature: OSType(0x594C5243), id: id.rawValue) // "YLRC"
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
    nonisolated func handleHotkey(id: UInt32) {
        DispatchQueue.main.async {
            guard let hotkeyID = HotkeyID(rawValue: id) else { return }
            switch hotkeyID {
            case .toggleOverlay: self.onToggleOverlay?()
            case .toggleAll: self.onToggleAll?()
            case .offsetPlus: self.onOffsetPlus?()
            case .offsetMinus: self.onOffsetMinus?()
            case .offsetReset: self.onOffsetReset?()
            }
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
    HotkeyManager.shared.handleHotkey(id: hotkeyID.id)
    return noErr
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds (warnings about Sendable are OK).

- [ ] **Step 3: Commit**

```bash
git add Sources/App/HotkeyManager.swift
git commit -m "feat: add HotkeyManager with Carbon hot key registration"
```

---

### Task 3: AppConfig Shortcut Keys

**Files:**
- Modify: `Sources/App/AppConfig.swift` (add `Shortcuts` enum at line 143, before the `Key` struct)

- [ ] **Step 1: Add Shortcuts config keys**

In `Sources/App/AppConfig.swift`, add a new section after the `Widget` enum (after line 143) and before the `Key` struct (line 147):

```swift
    // MARK: - Shortcuts

    enum Shortcuts {
        static let enabled = Key<Bool>("shortcuts.enabled", default: true)
        static let toggleOverlay = Key<String>("shortcuts.toggleOverlay", default: "ctrl+opt+l")
        static let toggleAll = Key<String>("shortcuts.toggleAll", default: "ctrl+opt+h")
        static let offsetPlus = Key<String>("shortcuts.offsetPlus", default: "ctrl+opt+right")
        static let offsetMinus = Key<String>("shortcuts.offsetMinus", default: "ctrl+opt+left")
        static let offsetReset = Key<String>("shortcuts.offsetReset", default: "ctrl+opt+0")
    }
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/AppConfig.swift
git commit -m "feat: add AppConfig.Shortcuts keys for global hotkey bindings"
```

---

### Task 4: AppDelegate Integration

**Files:**
- Modify: `Sources/App/AppDelegate.swift`

- [ ] **Step 1: Add toggle state and new methods**

Add a new property after `hasEverPlayed` (line 21):

```swift
    private var allDisplaysHidden = false
```

Add new methods before `applicationWillTerminate` (before line 363):

```swift
    // MARK: - Hotkey Actions

    private func toggleOverlayVisibility() {
        if isOverlayHidden {
            cancelAutoHide()
            showOverlay()
        } else {
            cancelAutoHide()
            hideOverlay()
        }
    }

    private func toggleAllDisplays() {
        allDisplaysHidden.toggle()
        if allDisplaysHidden {
            cancelAutoHide()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.overlayWindow?.animator().alphaValue = 0
                self.desktopWidget?.animator().alphaValue = 0
            }
            menuBarController?.updateCurrentLine("")
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.overlayWindow?.animator().alphaValue = 1
                self.desktopWidget?.animator().alphaValue = 1
            }
            isOverlayHidden = false
            lastDisplayedLineIndex = -2  // force redraw
            updateAllDisplays()
        }
    }

    private func nudgeOffset(_ delta: TimeInterval) {
        SettingsManager.shared.lyricsOffset += delta
    }

    private func resetOffset() {
        SettingsManager.shared.lyricsOffset = 0
    }
```

- [ ] **Step 2: Wire up HotkeyManager in applicationDidFinishLaunching**

In `applicationDidFinishLaunching`, add after `playerManager.startPolling()` (after line 35):

```swift
        let hk = HotkeyManager.shared
        hk.onToggleOverlay = { [weak self] in self?.toggleOverlayVisibility() }
        hk.onToggleAll = { [weak self] in self?.toggleAllDisplays() }
        hk.onOffsetPlus = { [weak self] in self?.nudgeOffset(0.5) }
        hk.onOffsetMinus = { [weak self] in self?.nudgeOffset(-0.5) }
        hk.onOffsetReset = { [weak self] in self?.resetOffset() }
        hk.registerAll()
```

- [ ] **Step 3: Add cleanup in applicationWillTerminate**

In `applicationWillTerminate`, add before the existing cleanup:

```swift
        HotkeyManager.shared.unregisterAll()
```

- [ ] **Step 4: Guard allDisplaysHidden in updateAllDisplays**

At the top of `updateAllDisplays()` (line 254), add an early return:

```swift
        guard !allDisplaysHidden else { return }
```

- [ ] **Step 5: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 6: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass (including the new HotkeyTests from Task 1).

- [ ] **Step 7: Commit**

```bash
git add Sources/App/AppDelegate.swift
git commit -m "feat: wire HotkeyManager actions in AppDelegate"
```

---

### Task 5: Settings UI — Shortcuts Tab

**Files:**
- Modify: `Sources/Settings/SettingsView.swift`

- [ ] **Step 1: Add Shortcuts tab to SettingsContentView**

In `SettingsContentView.body` (line 100), add a new tab after the Sources tab:

```swift
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
```

- [ ] **Step 2: Increase window height for the new tab**

Change the frame height on line 108 from `460` to `500`:

```swift
        .frame(width: 500, height: 500)
```

- [ ] **Step 3: Add ShortcutsTab view**

Add the following struct before the `LabeledSlider` helper (before line 462):

```swift
// MARK: - Shortcuts Tab

struct ShortcutsTab: View {
    @State private var shortcutsEnabled = AppConfig.get(AppConfig.Shortcuts.enabled)

    private let shortcuts: [(String, String, AppConfig.Key<String>)] = [
        ("Toggle Overlay", "Show/hide the floating overlay", AppConfig.Shortcuts.toggleOverlay),
        ("Toggle All Displays", "Show/hide all displays at once", AppConfig.Shortcuts.toggleAll),
        ("Offset +0.5s", "Lyrics appear earlier", AppConfig.Shortcuts.offsetPlus),
        ("Offset -0.5s", "Lyrics appear later", AppConfig.Shortcuts.offsetMinus),
        ("Reset Offset", "Reset lyrics timing to default", AppConfig.Shortcuts.offsetReset),
    ]

    var body: some View {
        Form {
            Section("Global Shortcuts") {
                Toggle("Enable global shortcuts", isOn: $shortcutsEnabled)
                    .onChange(of: shortcutsEnabled) { newValue in
                        AppConfig.set(AppConfig.Shortcuts.enabled, newValue)
                        if newValue {
                            HotkeyManager.shared.registerAll()
                        } else {
                            HotkeyManager.shared.unregisterAll()
                        }
                    }
            }

            if shortcutsEnabled {
                Section("Key Bindings") {
                    ForEach(shortcuts, id: \.0) { name, detail, key in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ShortcutParser.displayString(AppConfig.get(key)))
                                .font(.system(.body, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.15))
                                )
                        }
                    }
                }

                Section {
                    Text("Customize shortcuts in ~/.config/yalyric/config.toml")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 5: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Settings/SettingsView.swift
git commit -m "feat: add Shortcuts tab to Settings UI"
```

---

### Task 6: TOML Config Export Support

**Files:**
- Modify: `Sources/App/AppConfig.swift` (update `exportConfig`)

- [ ] **Step 1: Add shortcuts section to exportConfig**

In `AppConfig.exportConfig()`, add a new section to the `sections` array (after the theme section):

```swift
            ("shortcuts", "Global keyboard shortcuts", [
                ("enabled", get(Shortcuts.enabled)),
                ("toggleOverlay", get(Shortcuts.toggleOverlay)),
                ("toggleAll", get(Shortcuts.toggleAll)),
                ("offsetPlus", get(Shortcuts.offsetPlus)),
                ("offsetMinus", get(Shortcuts.offsetMinus)),
                ("offsetReset", get(Shortcuts.offsetReset)),
            ]),
```

- [ ] **Step 2: Build and test**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: Build succeeds, all tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/AppConfig.swift
git commit -m "feat: include shortcuts in TOML config export"
```

---

### Task 7: Final Integration Test

**Files:** None (manual verification)

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1`
Expected: All tests pass, including the 13 new HotkeyTests.

- [ ] **Step 2: Build release**

Run: `swift build -c release 2>&1 | tail -3`
Expected: Release build succeeds.

- [ ] **Step 3: Manual smoke test**

Run the app: `swift build && .build/debug/yalyric`

Verify:
1. App launches normally with no console errors about hotkeys
2. Open Settings → Shortcuts tab shows 5 shortcuts with key bindings
3. Toggle "Enable global shortcuts" off and on — check log for register/unregister messages
4. With Spotify playing: press `⌃⌥L` — overlay should hide/show
5. Press `⌃⌥H` — all displays hide/show
6. Press `⌃⌥→` / `⌃⌥←` — offset changes in Settings
7. Press `⌃⌥0` — offset resets to 0

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: global keyboard shortcuts (⌃⌥L/H/←/→/0) with Carbon Hot Keys"
```
