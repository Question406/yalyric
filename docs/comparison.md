# yalyric vs Alternatives

> Last updated: 2026-03-26

## Landscape

| App | Status | macOS | Sources | Display Modes | Word Karaoke | Stars |
|-----|--------|-------|---------|---------------|-------------|-------|
| **yalyric** | Active | 13+ | 4 (parallel) | Overlay, Widget, Menu Bar | Line-level | New |
| **LyricsX** (original) | Abandoned (2022) | 10.11+ | ~6 (many broken) | Desktop, Menu Bar, Touch Bar | Word-level | 5.1K |
| **LyricsX** (MxIris fork) | Active | 11+ | 8 (added LRCLIB, Musixmatch) | Desktop, Menu Bar | Word-level | — |
| **LyricFever** | Active | **15+** | 3 | Menu Bar, Fullscreen, Popup | Word-level | 551 |
| **Spotify built-in** | N/A | N/A | 1 (Musixmatch) | In-app only | Word-level | N/A |

## yalyric Strengths

- **macOS 13+** — works on Ventura through latest, while LyricFever requires Sequoia (15+)
- **Parallel provider fetching** — all 4 sources queried concurrently with scoring; others use sequential waterfall
- **Shared search validation** — name/artist/duration scoring prevents wrong-song matches
- **Disk + memory cache** — instant lyrics on replay; LRU eviction
- **Lean codebase** — ~4K lines Swift, zero dependencies, easy to understand and contribute
- **TOML config file** — power user configuration at `~/.config/yalyric/config.toml`
- **Adaptive polling** — 0.5s while playing, 2s idle (lower CPU when paused)
- **Podcast/DJ filtering** — auto-detects non-music content, hides lyrics
- **Active development** — modern Swift concurrency, Combine, structured logging

## yalyric Gaps (vs competition)

- **No word-level karaoke** — only line-level gradient fill (Level 2 planned, Spotify API has the data)
- **No Apple Music support** — Spotify only (AppleScript bridge planned)
- **No click-to-seek** — can't click a lyric line to jump to that timestamp
- **No local .lrc import/export** — planned
- **No code signing** — requires `xattr -cr` on first launch
- **No screenshots/GIF yet** — need visual showcase

## Positioning

yalyric targets the gap between:
1. **LyricsX users** whose app broke on modern macOS and need a replacement
2. **LyricFever's macOS 15+ requirement** excludes Ventura/Sonoma users
3. **Developers** who want a clean, hackable, zero-dependency lyrics app to extend

Key message: "LyricsX is broken on modern macOS. yalyric is a fresh, native alternative with parallel lyrics fetching and karaoke fill."

## Promotion Channels

- **r/macapps**, **r/spotify** — "I built an open-source Spotify lyrics overlay"
- **Hacker News** (Show HN) — native Swift, zero deps, clean architecture
- **V2EX** — CJK lyrics support (NetEase + language detection) is strong for Chinese dev audience
- **GitHub Topics** — tag with `macos`, `spotify`, `lyrics`, `swift`, `desktop-lyrics`

## Priority to Close Gaps

1. Screenshots/GIF — nothing else matters for promotion without visuals
2. v0.2.0 release tag — proper .app bundle signals maturity
3. Word-level karaoke (Level 2) — the "wow" feature for screenshots
4. Apple Music support — doubles the audience
5. Code signing — removes the `xattr` friction
