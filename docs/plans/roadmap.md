# yalyric — Product Roadmap

> From working demo to a real app people want to use.

## Current State (v0.1)

What works today:
- Spotify track detection via AppleScript
- Lyrics fetching from 4 sources (LRCLIB, Spotify internal, Musixmatch, NetEase)
- 3 display modes (overlay, desktop widget, menu bar)
- Basic settings window (display modes, font size, SP_DC cookie, lyrics language)
- Slide-up crossfade animation on overlay
- Track metadata shown during intro/loading
- Language preference filtering (Auto/specific language)
- Duration-based lyrics matching to reduce song mismatch
- `.app` bundle via `scripts/bundle.sh`
- GitHub Actions CI (build + test) and release workflow (tag → zip → GitHub Release)
- Homebrew cask auto-publish workflow (release → update tap repo)

---

## P0 — Must Have Before First Public Release

These are blockers. Without them, users will try yalyric once and never open it again.

### 1. App Bundle & Distribution
**Why:** Normal users need a standard install path.

- [x] Create proper `.app` bundle with Info.plist, icon, bundle ID
- [x] Add `NSAppleEventsUsageDescription` for Spotify permission dialog
- [x] Build script: `./scripts/bundle.sh` → builds release + creates `.app` + zips
- [x] GitHub Releases with downloadable `.zip` per version
- [x] GitHub Actions CI: build + test on push, create release artifacts on tag
- [x] Homebrew cask auto-publish workflow
- [ ] Homebrew tap repo setup and first publish (see Homebrew section below)
- [ ] Code signing + notarization ($99/year Apple Developer) — eliminates "damaged app" and `xattr -cr` workaround
- [ ] DMG with drag-to-Applications layout (nicer than zip)

### 2. First Launch Experience
**Why:** User opens the app, Spotify is playing, and... nothing happens for a confusing few seconds.

- [x] Detect when Spotify is playing but no lyrics found — show track name + "No lyrics available"
- [x] Show track metadata during intro before lyrics start
- [ ] Show a brief onboarding overlay on first launch: "yalyric is running — play a song in Spotify to see lyrics"
- [ ] Detect when AppleScript permission is denied and show a clear message with link to System Settings
- [ ] Detect when Spotify is not running and show "Waiting for Spotify..." instead of blank

### 3. Lyrics Reliability
**Why:** The #1 reason users will judge this app is whether lyrics actually show up.

- [x] Duration-based matching on LRCLIB search (5s tolerance)
- [x] Reject NetEase results with large duration mismatch
- [x] Race condition fix: verify track hasn't changed before applying fetched lyrics
- [x] 5s request timeout on all provider HTTP requests
- [x] Language preference filtering (Auto/specific)
- [x] LRCLIB search scoring: prefer exact artist/track name + synced lyrics
- [ ] Parallel provider fetching — query all 4 concurrently, pick best result
- [ ] Retry failed fetches once after 2s (network blips)
- [ ] Show lyrics source in small text ("via LRCLIB") so users know what's working
- [ ] Manual offset adjustment (+/- seconds) for out-of-sync lyrics

### 4. Overlay UX Polish
**Why:** The overlay is the primary display mode.

- [x] Smooth slide-up crossfade transition (no flashing)
- [ ] **Draggable positioning** — hold Option to enter edit mode, save position
- [ ] **Auto-hide when Spotify is paused/stopped**
- [ ] **Auto-hide when no lyrics**
- [ ] **Adaptive text color** — auto white/dark based on background
- [ ] **Background pill** — optional semi-transparent rounded rect
- [ ] **Multi-monitor support**

---

## P1 — Should Have for User Retention

These make the difference between "neat tool" and "I actually keep this running."

### 5. Menu Bar Improvements
- [ ] Left-click shows lyrics popover, right-click shows menu (Settings/Quit)
- [ ] Scrolling lyrics in popover with smooth auto-follow
- [ ] Click a lyric line to seek Spotify to that timestamp
- [ ] Show album art + track info at top of popover
- [ ] Progress bar in popover

### 6. Desktop Widget Improvements
- [ ] Draggable position
- [ ] Configurable visible line count (3/5/7)
- [ ] Optional album art background with blur
- [ ] Smooth scroll animation when lines change

### 7. Keyboard Shortcuts
- [ ] Global hotkey to toggle overlay (e.g., ⌘⇧L)
- [ ] Global hotkey to toggle all displays
- [ ] Nudge lyric offset +0.5s / -0.5s
- [ ] Open/close lyrics popover

### 8. Settings Overhaul
- [ ] Rewrite with SwiftUI (NSHostingController)
- [ ] Tabbed: General / Appearance / Sources / Shortcuts
- [ ] Live preview of appearance changes

### 9. Performance & Stability
- [ ] Move AppleScript polling off main thread (Process + osascript or ScriptingBridge)
- [ ] Cap lyrics cache (50 tracks LRU)
- [ ] Handle Spotify crash/restart gracefully
- [ ] Log file (`~/Library/Logs/yalyric.log`)

---

## P2 — Nice to Have

### 10. Visual Flair
- [ ] Karaoke mode — word-level highlighting
- [ ] Color sync from album art
- [ ] Vertical lyrics mode for CJK
- [ ] Animated gradient background

### 11. Local Lyrics Support
- [ ] Drag & drop `.lrc` file assignment
- [ ] Auto-scan `~/Music/Lyrics/` folder
- [ ] Built-in lyrics editor
- [ ] Export as `.lrc`

### 12. Social & Sharing
- [ ] Copy current line hotkey
- [ ] Share lyrics as image (album art background)
- [ ] Discord Rich Presence integration

### 13. Multi-Player Support
- [ ] Apple Music (AppleScript)
- [ ] Browser Spotify (extension)

### 14. Sync & Cloud
- [ ] iCloud sync for settings + offsets
- [ ] Community offset corrections to LRCLIB
- [ ] Per-track offset persistence

---

## P3 — Future / Exploratory

- [ ] iOS companion app
- [ ] Translation overlay
- [ ] AI-powered lyrics search
- [ ] Spotify Web API OAuth integration
- [ ] VoiceOver / accessibility

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

Homebrew automatically handles:
- Downloading the zip
- Extracting the `.app`
- Moving to `/Applications`
- Removing quarantine flags (no `xattr -cr` needed)
- Updates via `brew upgrade`

---

## Suggested Release Plan

### v0.1 — "It works" ✅
Demo quality. `.app` bundle, CI, basic lyrics sync.

### v0.2 — "I can actually use this"
Complete remaining P0: onboarding, permission detection, draggable overlay, auto-hide, Homebrew tap.
Target: 2 weeks.

### v0.5 — "I want to keep using this"
P1: menu bar popover, keyboard shortcuts, SwiftUI settings, performance.
Target: 3-4 weeks after v0.2.

### v1.0 — "I'd recommend this"
Cherry-pick P2: karaoke mode, local lyrics, sharing.
Code signing + notarization.
Target: 2-3 months.

---

## Success Metrics

1. **Lyrics hit rate** — >80% for English pop/rock
2. **Time to first lyric** — <2s from song start
3. **Daily active usage** — launch-at-login adoption rate
4. **GitHub stars / Homebrew installs**
5. **Issue reports** — people caring enough to report = good sign
