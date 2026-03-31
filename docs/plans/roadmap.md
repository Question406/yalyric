# yalyric — Product Roadmap

> From working demo to a real app people want to use.

## Current State (v0.2.3)

What works today:
- Spotify + Apple Music detection via AppleScript (auto-detects active player)
- Lyrics fetching from 4 sources in parallel (LRCLIB, Spotify internal, Musixmatch, NetEase)
- Smart scoring: synced(+3), language match(+1), line count(+1), early return on perfect score
- 3 display modes (overlay, desktop widget, menu bar popover)
- SwiftUI settings with 4 tabs (General, Appearance, Sources, Shortcuts)
- 6 theme presets + full customization (font, color, transitions, background styles)
- Global keyboard shortcuts (⌃⌥ prefix, Carbon Hot Keys, no accessibility permission)
- Multi-display support: 4 modes (Follow Mouse, Follow Focused Window, Pin to Screen, Show on All) — awaiting multi-monitor testing
- Karaoke fill (horizontal gradient sweep on current line)
- Draggable overlay + widget positioning with custom position persistence
- Auto-hide overlay on pause (configurable delay)
- Menu bar popover with scrolling lyrics, auto-follow, provider/sync info
- Manual lyrics offset adjustment (+/- 0.5s)
- Two-tier cache: LRU memory (50) + disk JSON (200)
- First-launch onboarding + AppleScript permission detection
- Logging to `~/Library/Logs/yalyric.log` with rotation
- `.app` bundle, GitHub Actions CI/CD, Homebrew cask distribution

---

## Completed (P0 — Distribution & First Launch)

- [x] `.app` bundle with Info.plist, icon, bundle ID
- [x] `NSAppleEventsUsageDescription` for permission dialog
- [x] Build script: `./scripts/bundle.sh`
- [x] GitHub Releases with downloadable `.zip`
- [x] GitHub Actions CI: build + test on push, release on tag
- [x] Homebrew cask auto-publish workflow
- [x] Homebrew tap repo setup and first publish
- [x] Onboarding overlay on first launch
- [x] AppleScript permission denied detection with clear message
- [x] Non-music content detection (podcasts, ads)

## Completed (P0 — Lyrics Reliability)

- [x] Duration-based matching on LRCLIB search (5s tolerance)
- [x] Reject results with large duration mismatch (all providers)
- [x] Race condition fix: verify track hasn't changed before applying
- [x] 5s request timeout on all provider HTTP requests
- [x] Language preference filtering (Auto/specific)
- [x] Search scoring: name(+3), artist(+3), duration(+2), min score 3
- [x] Parallel provider fetching with early return on perfect score
- [x] Lyrics source display ("via LRCLIB · synced")
- [x] Manual offset adjustment (+/- 0.5s)

## Completed (P0 — Overlay UX)

- [x] Smooth transitions (crossfade, slide-up, scale-fade, push)
- [x] Draggable positioning via menu bar toggle
- [x] Auto-hide when paused/stopped (configurable delay)
- [x] Background styles (none, frosted pill, solid pill, full-width bar)
- [x] Dynamic width (resizes to fit text, centered on anchor)

## Completed (P1 — Menu Bar & Widget)

- [x] Left-click shows lyrics popover, right-click shows menu
- [x] Scrolling lyrics in popover with smooth auto-follow
- [x] Karaoke fill progress in menu bar
- [x] Desktop widget with draggable position
- [x] Configurable widget line count (3/5/7/9)

## Completed (P1 — Settings & Performance)

- [x] SwiftUI settings (NSHostingController) with 4 tabs
- [x] LRU memory cache (50) + disk cache (200) with eviction
- [x] Log file with rotation (2MB max)
- [x] Apple Music support

## Completed (P1 — Keyboard Shortcuts)

- [x] Global hotkey to toggle overlay visibility (⌃⌥L)
- [x] Global hotkey to toggle all displays (⌃⌥H)
- [x] Nudge lyric offset +0.5s / -0.5s via hotkey (⌃⌥→ / ⌃⌥←)
- [x] Reset offset via hotkey (⌃⌥0)
- [x] Settings UI: Shortcuts tab with enable toggle and key binding display
- [x] TOML config for customizing key bindings
- [x] Carbon Hot Keys API (no accessibility permission required)

## Completed (P1 — Multi-Display Support)

- [x] 4 display behavior modes (Follow Mouse, Follow Focused Window, Pin to Screen, Show on All)
- [x] Independent config for overlay and widget
- [x] Relative position storage for cross-screen compatibility
- [x] Monitor hot-plug handling (didChangeScreenParametersNotification)
- [x] Settings UI with display behavior pickers
- [x] No new permissions required (polling-based detection)

---

## Up Next

### Multi-Display Testing (P1) ⏳
**Why:** Multi-display support is implemented but needs real multi-monitor testing.

- [x] Follow Mouse mode (overlay follows mouse cursor between monitors)
- [x] Follow Focused Window mode (overlay follows NSScreen.main)
- [x] Pin to Screen mode (user picks specific monitor)
- [x] Show on All mode (one instance per screen)
- [x] Relative position storage (custom positions transfer across screens)
- [x] Monitor hot-plug handling
- [x] Settings UI with per-display-mode config for overlay and widget
- [ ] Manual testing on multi-monitor setup
- [ ] Verify crossfade animation when moving between screens
- [ ] Verify "Show on All" edit mode targets correct window

### Word-Level Karaoke (P2)
**Why:** Per-word highlighting is a major visual upgrade over per-line fill.

- [ ] Parse Spotify `syllables[]` data from internal API
- [ ] Word-level gradient mask with per-syllable timing
- [ ] Fallback to line-level fill when syllable data unavailable

### Screenshots & Promotion (P0)
**Why:** No one installs an app without seeing it first.

- [ ] Screenshots of all 3 display modes for README
- [ ] Animated GIF/video showing lyrics sync in action
- [ ] Update README with visuals and feature list

---

## Backlog

### Distribution
- [ ] Code signing + notarization ($99/yr Apple Developer)
- [ ] DMG with drag-to-Applications layout

### Popover Enhancements
- [ ] Click a lyric line to seek player to that timestamp
- [ ] Album art + track info header
- [ ] Progress bar

### Visual Features
- [ ] Adaptive text color based on desktop background
- [ ] Color sync from album art
- [ ] Vertical lyrics mode for CJK
- [ ] Animated gradient background

### System Integration
- [ ] Launch at login (SMAppService)
- [ ] Retry failed fetches once after 2s

### Local Lyrics
- [ ] Drag & drop `.lrc` file assignment
- [ ] Auto-scan `~/Music/Lyrics/` folder
- [ ] Built-in lyrics editor
- [ ] Export as `.lrc`

### Social & Sharing
- [ ] Copy current line hotkey
- [ ] Share lyrics as image (album art background)

---

## Future / Exploratory

- [ ] iOS companion app
- [ ] Translation overlay
- [ ] AI-powered lyrics search
- [ ] Spotify Web API OAuth integration
- [ ] VoiceOver / accessibility
- [ ] Per-track offset persistence
- [ ] Community offset corrections

---

## Homebrew Distribution

### Setup (one-time)

1. Create repo `yourname/homebrew-tap` on GitHub
2. Generate a Personal Access Token (PAT) with `repo` scope
3. Add as secret `HOMEBREW_TAP_TOKEN` in yalyric repo Settings → Secrets → Actions

### How it works

The `.github/workflows/homebrew.yml` workflow triggers on every published release:
1. Downloads the release zip
2. Computes SHA256 hash
3. Writes/updates `Casks/yalyric.rb` in the tap repo with new version + hash + URL
4. Commits and pushes to the tap

### User install

```bash
brew tap yourname/tap
brew install --cask yalyric
```
