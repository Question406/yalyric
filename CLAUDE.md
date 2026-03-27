# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
swift build && .build/debug/yalyric     # Build and run
swift build -c release                   # Release build
./scripts/bundle.sh 0.2.0               # Create .app bundle → dist/yalyric.app
swift test                               # Run all 63 tests (requires Xcode: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer)
```

The app appears as a music note icon in the menu bar. Needs Spotify desktop app running.

## Architecture

yalyric is a native macOS menu bar app (Swift/AppKit, SPM, no external dependencies) that syncs Spotify and Apple Music lyrics to the desktop.

### Target Split

- **yalyricLib** (library, `Sources/`) — all logic, excluded `App/main.swift`
- **yalyric** (executable, `Executable/`) — 7-line entry point, depends on yalyricLib
- **yalyricTests** (tests, `Tests/`) — XCTest, depends on yalyricLib

### Data Flow

```
PlayerManager (auto-detects Spotify / Apple Music)
    ↓ SpotifyBridge + AppleMusicBridge (AppleScript poll 0.5s/2s each)
    ↓ $currentTrack, $isPlaying, $playbackPosition (Combine @Published)
AppDelegate (wires everything via Combine .sink)
    ↓ track change → LyricsManager.fetchLyrics(for:)
LyricsManager (parallel providers + scoring + LRU/disk cache)
    ↓ $currentLyrics → SyncEngine.setLyrics()
SyncEngine (binary search on timestamps, computes progress 0-1)
    ↓ currentLine, nextLine, progress
AppDelegate.updateAllDisplays()
    ↓ dispatches to all enabled display modes
OverlayWindow / DesktopWidget / MenuBarController
```

### Key Components

- **PlayerManager**: Auto-detects active player (Spotify or Apple Music), forwards unified stream. Prefers Spotify when both are playing.

- **AppleScriptBridge** (base class): Adaptive polling (0.5s playing, 2s idle), pre-compiled script, dedicated serial scriptQueue, 3s timeout. SpotifyBridge and AppleMusicBridge inherit from it. Adding a new player = subclass + override `compiledScript` and `parseResult`.

- **SpotifyBridge**: Filters non-music content (`spotify:track:` prefix). Duration in ms. **AppleMusicBridge**: Uses `database ID`. Duration in seconds.

- **LyricsManager**: Queries all 4 providers concurrently via `withTaskGroup`. Scoring: synced(+3), langMatch(+1), lines>5(+1). Early return on perfect score. Two-tier cache: LRU memory (50) + disk JSON (200).

- **SearchMatchScore** (in `LyricsProvider.swift`): Shared validation for search-based providers. Scores name(+3), artist(+3), duration(+2). Minimum score 3 required. All providers must use this for result validation.

- **ThemeManager**: Singleton with `@Published var theme`. Changes debounced 0.3s before UserDefaults save. Display modes subscribe via Combine. 6 presets. Karaoke fill settings preserved across preset switches.

- **OverlayWindow**: Dual A/B label pattern for transitions. CAGradientLayer mask for karaoke fill with CABasicAnimation interpolation. Dynamic width (resizes to fit text, centered). Position changes only when position-related theme properties change (posKey tracking).

### Important Gotchas

- **NSAnimationContext vs CATransaction**: Use NSAnimationContext for AppKit `animator()` proxy properties. Use CATransaction for CALayer properties (transforms, gradient locations). They can run concurrently.
- **`animator()` crashes in global event monitors**: Use `allowsImplicitAnimation` or timers instead of `animator()` in `NSEvent.addGlobalMonitorForEvents` callbacks.
- **`attributedStringValue` overrides label alignment**: Always include `NSParagraphStyle` with `.center` when setting `attributedStringValue` on labels.
- **`NSWindow.alphaValue` needs `animator()`**: `allowsImplicitAnimation` does NOT animate window-level `alphaValue`. Must use `window.animator().alphaValue`.
- **Desktop-level windows can't receive drags**: Temporarily raise to `.floating` level during edit mode.
- **Theme changes cascade**: Setting `ThemeManager.shared.theme` triggers Combine → applyTheme on all displays → can rebuild backgrounds. Avoid in hot paths. Use `isLocking` flags when saving position.
- **Musixmatch captcha**: Token gets rate-limited. Persisted to UserDefaults with 1hr expiry. Browser-like User-Agent helps.

## Logging

Use `YalyricLog.info()` / `.error()` instead of `print()`. Writes to `~/Library/Logs/yalyric.log` + console. All log lines prefixed `[yalyric]`.

## Testing

Tests are in `Tests/` — 5 files, 63 tests. Key areas:
- `SyncEngineTests`: timestamp matching, offset, progress calculation
- `LyricsModelTests`: binary search, lyrics scoring
- `ThemeTests`: equality, gradient location math
- `LRCParserTests`: LRC format parsing (time tags, plain text, edge cases)
- `TrackInfoTests`: Spotify ID extraction
