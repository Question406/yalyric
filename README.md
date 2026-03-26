# yalyric

**Yet Another Lyric** sync for Spotify on macOS.

A native macOS menu bar app that displays synced lyrics for the currently playing Spotify track. Built with Swift and AppKit — no Electron, no web views, no bloat.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/License-Apache%202.0-green)

## Why?

[LyricsX](https://github.com/ddddxxx/LyricsX) was the gold standard for macOS lyrics — but it's been [abandoned since 2024](https://github.com/ddddxxx/LyricsX/issues/640), broken on macOS Sonoma/Sequoia, and its lyrics sources are mostly dead. [SpotifyLyrics](https://github.com/SimonIT/spotifylyrics) hasn't been updated since 2021 and relies on fragile web scraping.

yalyric fills the gap with a fresh native app, modern lyrics APIs, and support for current macOS versions.

## Features

### Three Display Modes

| Mode | Description |
|---|---|
| **Floating Overlay** | Always-on-top transparent window with current + next line. Click-through — doesn't interfere with your work. |
| **Desktop Widget** | Sits on the wallpaper layer showing 5 lines with the current line highlighted. Blurred background card. |
| **Menu Bar** | Shows the current lyric in the menu bar. Click to open a popover with full scrolling lyrics. |

All modes can be enabled/disabled independently from Settings.

### Four Lyrics Sources

Providers are tried in waterfall order — the first one to return synced lyrics wins:

| Source | Auth Required | Notes |
|---|---|---|
| [LRCLIB](https://lrclib.net) | None | Free, open API. Great coverage for English/Western music. |
| Spotify Internal | SP_DC cookie | Returns the exact lyrics Spotify shows natively (via Musixmatch). Best match quality. |
| Musixmatch | Auto-token | Large synced subtitle database. Token is generated automatically. |
| NetEase Cloud Music | None | Excellent for CJK (Chinese/Japanese/Korean) music. |

### Other Highlights

- **Native Swift/AppKit** — lightweight, ~65MB RAM, no Electron
- **0.5s polling** — accurate lyric sync via AppleScript
- **Binary search** sync engine — O(log n) timestamp matching
- **In-memory cache** — lyrics are fetched once per track
- **LRC format support** — standard `[MM:SS.xx]` timed lyrics
- **Plain lyrics fallback** — shows unsynced lyrics when no timed version is available
- **No dock icon** — lives entirely in the menu bar

## Requirements

- macOS 13 (Ventura) or later
- Spotify desktop app (not the web player)
- Swift 5.9+ / Xcode Command Line Tools

## Installation

### Download (easiest)

1. Download `yalyric-vX.X.X-macos.zip` from [GitHub Releases](https://github.com/yourname/yalyric/releases)
2. Unzip and drag `yalyric.app` to `/Applications`
3. Remove the quarantine flag (required for unsigned apps):
   ```bash
   xattr -cr /Applications/yalyric.app
   ```
4. Double-click to launch

> **Why step 3?** macOS quarantines apps downloaded from the internet. Without code signing, the app shows *"yalyric is damaged"* — it's not actually damaged, just unsigned. The `xattr -cr` command removes the quarantine flag.

### Build from Source

```bash
git clone https://github.com/yourname/yalyric.git
cd yalyric

# Build .app bundle
./scripts/bundle.sh
# Output: dist/yalyric.app

# Or run directly during development
swift build && .build/debug/yalyric
```

The app appears as a ♪ icon in the menu bar. Play a song in Spotify and lyrics will appear.

## Configuration

Click the menu bar icon to access **Settings**.

### Display Modes

Toggle any combination of the three display modes. Default: Floating Overlay + Menu Bar.

### Spotify Internal Lyrics (Optional)

To use Spotify's own lyrics API (best quality):

1. Open [open.spotify.com](https://open.spotify.com) in your browser
2. Log in to your Spotify account
3. Open DevTools (F12) → Application → Cookies
4. Copy the value of the `sp_dc` cookie
5. Paste it into yalyric Settings → SP_DC Cookie field

This is optional — LRCLIB works without any configuration.

### Font Size

Adjustable from 12pt to 48pt via the slider in Settings.

## Architecture

```
yalyric/
├── Package.swift
├── Executable/
│   └── main.swift                     # Entry point
├── Sources/
│   ├── App/
│   │   └── AppDelegate.swift          # App lifecycle, wires everything together
│   ├── Bridge/
│   │   └── SpotifyBridge.swift        # AppleScript polling for track info
│   ├── Lyrics/
│   │   ├── LRCParser.swift            # LRC format parser + data models
│   │   ├── LyricsManager.swift        # Orchestrates providers in waterfall
│   │   └── Providers/
│   │       ├── LyricsProvider.swift    # Protocol
│   │       ├── LRCLIBProvider.swift    # lrclib.net API
│   │       ├── SpotifyInternalProvider.swift
│   │       ├── MusixmatchProvider.swift
│   │       └── NetEaseProvider.swift
│   ├── Sync/
│   │   └── SyncEngine.swift           # Binary search timestamp matching
│   ├── Display/
│   │   ├── OverlayWindow.swift        # Floating transparent overlay
│   │   ├── DesktopWidget.swift        # Wallpaper-layer widget
│   │   └── MenuBarController.swift    # Menu bar + popover
│   ├── Settings/
│   │   └── SettingsView.swift         # Preferences window
│   └── Models/
│       └── TrackInfo.swift            # Track metadata model
└── Tests/
    ├── LRCParserTests.swift           # 16 tests
    ├── LyricsModelTests.swift         # 8 tests
    ├── TrackInfoTests.swift           # 4 tests
    └── SyncEngineTests.swift          # 18 tests
```

## Testing

```bash
swift test \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

46 tests across 4 suites covering LRC parsing, binary search sync, track info, and the sync engine.

If you have Xcode installed, `swift test` works without the extra flags.

## How It Works

1. **SpotifyBridge** polls the Spotify desktop app every 0.5 seconds via AppleScript to get the current track name, artist, album, Spotify ID, playback position, and play/pause state.

2. When the track changes, **LyricsManager** queries each lyrics provider in order. The first provider to return synced (timed) lyrics wins. Results are cached in memory by track ID.

3. **SyncEngine** uses binary search on the sorted lyric timestamps to find the current line for the given playback position. It publishes the current line, next line, line index, and intra-line progress.

4. **Display modes** subscribe to the sync engine and update their views — the overlay crossfades text, the widget highlights the current line, etc.

## Disclaimer

All lyrics are the property and copyright of their respective owners. yalyric fetches lyrics from third-party APIs for personal use only. This project is not affiliated with Spotify, Musixmatch, or any lyrics provider.

## License

[Apache License 2.0](LICENSE)
