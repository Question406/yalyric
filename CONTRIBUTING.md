# Contributing to yalyric

Thanks for your interest in contributing! yalyric is a small project and every contribution helps.

## Getting Started

### Prerequisites

- macOS 13+
- Swift 5.9+ (comes with Xcode or Command Line Tools)
- Spotify desktop app (for testing)
- Xcode (for running tests locally — `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)

### Setup

```bash
git clone https://github.com/Question406/yalyric.git
cd yalyric
swift build
.build/debug/yalyric
```

The app appears as a music note in your menu bar. Play a song in Spotify to verify lyrics display.

### Running Tests

```bash
swift test
```

71 tests across 6 suites. All tests must pass before submitting a PR.

### Debug Logs

Logs are written to `~/Library/Logs/yalyric.log` and also printed to console. Run from terminal to see live output:

```bash
.build/debug/yalyric
```

Log lines are prefixed with `[yalyric]` for easy filtering.

## Project Structure

```
Sources/
  App/          — AppDelegate, AppConfig, Logger, TOMLParser
  Bridge/       — PlayerManager, PlayerBridge, AppleScriptBridge,
                  SpotifyBridge, AppleMusicBridge
  Lyrics/       — LyricsManager, LRCParser, Providers/
  Sync/         — SyncEngine (binary search timestamp matching)
  Display/      — OverlayWindow, DesktopWidget, MenuBarController
  Settings/     — Theme, ThemeManager, SettingsView (SwiftUI)
  Models/       — TrackInfo
Tests/          — XCTest suites
```

Key patterns:
- **PlayerBridge protocol** — adding a new player = subclass `AppleScriptBridge`, override `compiledScript` and `parseResult`
- **PlayerManager** — auto-detects active player, forwards unified stream to AppDelegate
- **Combine** for reactive bindings between components
- **AppConfig** — centralized typed keys with TOML override layer
- **ThemeManager** singleton with `@Published` theme, debounced UserDefaults persistence
- **Parallel provider fetching** with scoring — see `LyricsManager.swift`
- **SearchMatchScore** for shared validation across providers — see `LyricsProvider.swift`

## How to Contribute

### Reporting Bugs

Open an issue with:
- What you expected vs. what happened
- The song/artist that triggered the issue
- Relevant lines from `~/Library/Logs/yalyric.log`

### Suggesting Features

Open an issue describing the feature and why it's useful. Check `docs/plans/roadmap.md` first — it might already be planned.

### Submitting Code

1. Fork the repo and create a branch (`feat/my-feature` or `fix/my-bug`)
2. Make your changes
3. Run `swift test` — all tests must pass
4. Add tests for new functionality where possible
5. Submit a PR with a clear description of what and why

### What Makes a Good PR

- **Small and focused** — one feature or fix per PR
- **Tests included** for new logic (providers, scoring, sync engine)
- **No unrelated changes** — don't refactor code you didn't need to touch

## Areas Looking for Help

Check issues labeled `good first issue` for beginner-friendly tasks. Some areas that would benefit from contributions:

- **Additional player support** — Tidal, YouTube Music (subclass AppleScriptBridge or add new bridge type)
- **Keyboard shortcuts** — global hotkeys via `CGEvent`
- **Local .lrc file support** — drag & drop lyrics override
- **Translations** — localize the settings UI
- **Album art color extraction** — Core Image dominant color analysis

## Code Style

- Follow existing patterns in the codebase
- Use `YalyricLog.info()` / `.error()` instead of `print()`
- Keep provider validation consistent via `SearchMatchScore`
- NSParagraphStyle with `.center` in any `attributedStringValue` (see OverlayWindow for why)

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
