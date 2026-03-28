# Global Keyboard Shortcuts — Design Spec

## Overview

Add global keyboard shortcuts to yalyric so users can control the app without clicking the menu bar. Uses Carbon Hot Keys (RegisterEventHotKey) for zero dependencies and no accessibility permission requirement.

## Actions & Default Bindings

All shortcuts use `⌃⌥` (Control+Option) as the modifier to avoid conflicts with system shortcuts, Spotify, Chrome, VS Code, Slack, and other common macOS apps.

| Action | Default Shortcut | Key Code | Description |
|---|---|---|---|
| Toggle overlay | `⌃⌥L` | kVK_ANSI_L | Show/hide the floating overlay |
| Toggle all displays | `⌃⌥H` | kVK_ANSI_H | Show/hide overlay + widget + menu bar text |
| Offset +0.5s | `⌃⌥→` | kVK_RightArrow | Lyrics appear 0.5s earlier |
| Offset -0.5s | `⌃⌥←` | kVK_LeftArrow | Lyrics appear 0.5s later |
| Reset offset | `⌃⌥0` | kVK_ANSI_0 | Reset lyrics offset to 0 |

## Architecture

### New Files

**`Sources/App/HotkeyManager.swift`** — Singleton that owns all global hotkey registrations.

Responsibilities:
- Register/unregister Carbon hot keys on app launch and settings change
- Map Carbon event handler callback to Swift actions
- Store enabled/disabled state and custom key bindings in AppConfig
- Provide `register()` / `unregisterAll()` lifecycle methods

### Data Flow

```
Carbon Event Handler (C callback)
    → HotkeyManager.handleHotkey(id:)
    → DispatchQueue.main.async
    → AppDelegate action methods (toggleOverlay, nudgeOffset, etc.)
```

The Carbon event handler fires a C function pointer. We use a global dictionary mapping hotkey IDs to action closures. The callback dispatches to main thread before executing any UI work.

### HotkeyManager API

```swift
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    func registerAll()      // Called from applicationDidFinishLaunching
    func unregisterAll()    // Called from applicationWillTerminate

    // Actions — set by AppDelegate
    var onToggleOverlay: (() -> Void)?
    var onToggleAll: (() -> Void)?
    var onOffsetPlus: (() -> Void)?
    var onOffsetMinus: (() -> Void)?
    var onOffsetReset: (() -> Void)?
}
```

### Carbon Hot Key Registration

Each shortcut is registered with `RegisterEventHotKey()`:
- Unique ID (UInt32) per action
- Modifier flags mapped from `⌃⌥` → `controlKey | optionKey`
- Key code from `Carbon.HIToolbox` virtual key codes
- Event handler installed once via `InstallEventHandler` for `kEventHotKeyPressed`

A single event handler handles all hotkeys by switching on the hotkey ID.

### AppConfig Keys

```swift
enum AppConfig.Shortcuts {
    static let enabled = Key<Bool>("shortcuts.enabled", default: true)
    static let toggleOverlay = Key<String>("shortcuts.toggleOverlay", default: "ctrl+opt+l")
    static let toggleAll = Key<String>("shortcuts.toggleAll", default: "ctrl+opt+h")
    static let offsetPlus = Key<String>("shortcuts.offsetPlus", default: "ctrl+opt+right")
    static let offsetMinus = Key<String>("shortcuts.offsetMinus", default: "ctrl+opt+left")
    static let offsetReset = Key<String>("shortcuts.offsetReset", default: "ctrl+opt+0")
}
```

String format: `"ctrl+opt+l"` — parsed into modifier flags + key code at registration time. This format is human-readable in the TOML config file and straightforward to parse.

### Settings UI

Add a **Shortcuts** tab to the existing SwiftUI settings:

- Master toggle: "Enable global shortcuts"
- List of 5 actions with current binding displayed
- No custom key recorder in v1 — just show the defaults and allow enable/disable
- Note text: "Customize in ~/.config/yalyric/config.toml"

### AppDelegate Integration

AppDelegate wires up the action closures in `applicationDidFinishLaunching`:

```swift
let hk = HotkeyManager.shared
hk.onToggleOverlay = { [weak self] in self?.toggleOverlayVisibility() }
hk.onToggleAll = { [weak self] in self?.toggleAllDisplays() }
hk.onOffsetPlus = { [weak self] in self?.nudgeOffset(0.5) }
hk.onOffsetMinus = { [weak self] in self?.nudgeOffset(-0.5) }
hk.onOffsetReset = { [weak self] in self?.resetOffset() }
hk.registerAll()
```

New AppDelegate methods:
- `toggleOverlayVisibility()` — if overlay exists, toggle between hidden/shown (reuses existing `hideOverlay`/`showOverlay` but without auto-hide timer interference)
- `toggleAllDisplays()` — hide/show overlay + widget + clear menu bar text
- `nudgeOffset(_ delta: TimeInterval)` — adjusts `SettingsManager.shared.lyricsOffset`
- `resetOffset()` — sets offset to 0

### Toggle Behavior Details

**Toggle overlay:** Flips a manual visibility flag. When manually hidden, auto-hide timer is cancelled and the overlay stays hidden until toggled again or a new track starts.

**Toggle all:** Sets a global "all hidden" flag. When hidden: overlay alpha → 0, widget alpha → 0, menu bar shows no text. When shown: restores previous state. Does not destroy windows — just hides/shows them.

## Testing

- Unit test for shortcut string parsing (`"ctrl+opt+l"` → modifier flags + key code)
- Unit test for HotkeyManager action dispatch (mock actions, verify they're called)
- Carbon registration itself requires a running app — manual testing only

## Scope Boundaries

**In scope:**
- 5 global shortcuts with fixed defaults
- Enable/disable toggle in Settings
- TOML config override for power users
- Clean register/unregister lifecycle

**Out of scope (future):**
- Custom key recorder UI (record-a-shortcut widget)
- Per-shortcut enable/disable
- Conflict detection with other apps
