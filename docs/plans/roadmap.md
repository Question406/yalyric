# yalyric — Product Roadmap

> From working demo to a real app people want to use.

## Current State (Demo)

What works today:
- Spotify track detection via AppleScript
- Lyrics fetching from 4 sources (LRCLIB, Spotify internal, Musixmatch, NetEase)
- 3 display modes (overlay, desktop widget, menu bar)
- Basic settings window
- Slide-up crossfade animation on overlay

What's honestly missing: almost everything a real user would expect from a polished macOS app.

---

## P0 — Must Have Before First Public Release

These are blockers. Without them, users will try yalyric once and never open it again.

### 1. App Bundle & Distribution
**Why:** Right now you can only run a raw binary from terminal. Normal users can't use this.

- [ ] Create proper `.app` bundle with Info.plist, icon, bundle ID
- [ ] Add `NSAppleEventsUsageDescription` so macOS shows a proper permission dialog instead of silently failing
- [ ] Create a `Makefile` or script: `make install` → builds release + copies `.app` to `/Applications`
- [ ] Homebrew cask formula for `brew install --cask yalyric`
- [ ] GitHub Releases with downloadable `.dmg` or `.zip` per version
- [ ] GitHub Actions CI: build on push, create release artifacts on tag

### 2. First Launch Experience
**Why:** User opens the app, Spotify is playing, and... nothing happens for a confusing few seconds. Or worse, macOS blocks the AppleScript permission and the user sees nothing at all.

- [ ] Show a brief onboarding overlay or notification on first launch: "yalyric is running — play a song in Spotify to see lyrics"
- [ ] Detect when AppleScript permission is denied and show a clear message: "yalyric needs Automation permission for Spotify. Open System Settings → Privacy → Automation"
- [ ] Detect when Spotify is not running and show "Waiting for Spotify..." in the overlay instead of blank
- [ ] Detect when Spotify is playing but no lyrics found — show track name + "No lyrics available" (not just a generic message)

### 3. Lyrics Reliability
**Why:** The #1 reason users will judge this app is whether lyrics actually show up. Every miss is a reason to uninstall.

- [ ] Parallel provider fetching — query all 4 sources concurrently, pick the best result (most lines, synced > plain). Current waterfall is slow: if LRCLIB times out (3s), user waits before trying Spotify API.
- [ ] Smarter fallback: if one provider returns plain lyrics and another returns synced, always prefer synced even if it came second
- [ ] Configurable provider timeout (default 3s per provider)
- [ ] Retry failed fetches once after 2s (network blips happen)
- [ ] Show lyrics source in small text ("via LRCLIB") so users know what's working
- [ ] Manual offset adjustment (+/- seconds) for when lyrics are slightly out of sync — this is extremely common and LyricsX had it

### 4. Overlay UX Polish
**Why:** The overlay is the primary display mode. It needs to feel invisible when you don't need it and perfectly readable when you do.

- [ ] **Draggable positioning** — hold a modifier key (Option) or right-click to enter "edit mode" where the overlay becomes draggable. Save position in UserDefaults.
- [ ] **Auto-hide when Spotify is paused/stopped** — don't leave stale lyrics on screen
- [ ] **Auto-hide when no lyrics** — don't show empty overlay
- [ ] **Adaptive text color** — detect wallpaper/background brightness and switch between light/dark text (or let user pick)
- [ ] **Background pill** — optional semi-transparent rounded rect behind the text for readability on busy backgrounds
- [ ] **Multi-monitor support** — let user pick which screen the overlay appears on
- [ ] **Respect Do Not Disturb / Focus modes** — hide overlay during presentations

---

## P1 — Should Have for User Retention

These make the difference between "neat tool" and "I actually keep this running."

### 5. Menu Bar Improvements
- [ ] Left-click shows lyrics popover, right-click shows menu (Settings/Quit). Currently the menu overrides the popover entirely.
- [ ] Scrolling lyrics in the popover should auto-follow with smooth animation
- [ ] Click a lyric line in the popover to seek Spotify to that timestamp (AppleScript: `set player position to X`)
- [ ] Show album art + track info at the top of the popover
- [ ] Show a progress bar in the popover

### 6. Desktop Widget Improvements
- [ ] Draggable position (same pattern as overlay)
- [ ] Configurable number of visible lines (3/5/7)
- [ ] Optional album art background with blur
- [ ] Smooth scroll animation when lines change (currently snaps)

### 7. Keyboard Shortcuts
- [ ] Global hotkey to toggle overlay visibility (e.g., ⌘⇧L)
- [ ] Global hotkey to toggle all displays on/off
- [ ] Hotkey to nudge lyric offset +0.5s / -0.5s
- [ ] Hotkey to open/close lyrics popover

### 8. Settings Overhaul
The current settings window is functional but ugly (manual frame layout, no sections).

- [ ] Rewrite with SwiftUI (embedded in NSHostingController) for modern look
- [ ] Tabbed interface: General / Appearance / Sources / Shortcuts
- [ ] General: launch at login toggle, display mode toggles, auto-hide options
- [ ] Appearance: font picker, font size, text color, background style, opacity slider, overlay position reset
- [ ] Sources: enable/disable each provider, drag to reorder priority, SP_DC cookie field with "Test" button, timeout config
- [ ] Shortcuts: global hotkey configuration
- [ ] Live preview of appearance changes

### 9. Performance & Stability
- [ ] AppleScript polling is blocking on the main thread — move to a background thread with `Process` + `osascript` or use ScriptingBridge framework for non-blocking access
- [ ] Memory: cap lyrics cache size (e.g., 50 tracks LRU) so it doesn't grow unbounded in long sessions
- [ ] Handle Spotify crashing/restarting gracefully (currently will keep polling dead app)
- [ ] Crash reporting or at minimum a log file (`~/Library/Logs/yalyric.log`)

---

## P2 — Nice to Have

These are differentiators that make yalyric special, not just functional.

### 10. Visual Flair
- [ ] Karaoke mode — word-level highlighting that fills across the line as the song plays (needs word-level timestamps from Spotify API or Musixmatch rich sync)
- [ ] Color sync — extract dominant color from album art, tint the lyrics text/glow
- [ ] Vertical lyrics mode for CJK text
- [ ] Animated gradient background option for the overlay
- [ ] "Lyrics wallpaper" mode — render lyrics directly onto the desktop wallpaper with Core Image

### 11. Local Lyrics Support
- [ ] Drag & drop `.lrc` file to manually assign lyrics to a track
- [ ] Auto-scan a folder (e.g., `~/Music/Lyrics/`) for matching `.lrc` files
- [ ] Built-in lyrics editor — tap a line while the song plays to set its timestamp
- [ ] Export current lyrics as `.lrc` file

### 12. Social & Sharing
- [ ] "Copy current line" button/hotkey
- [ ] "Share lyrics" — generate a pretty image of 4-5 lines with album art background, copy to clipboard
- [ ] Integration with Discord Rich Presence to show current lyric

### 13. Multi-Player Support
- [ ] Apple Music support (AppleScript works the same way)
- [ ] Browser-based Spotify (would need a companion browser extension)
- [ ] Generic MPRIS-like support via Now Playing framework

### 14. Sync & Cloud
- [ ] iCloud sync for settings and custom lyric offsets
- [ ] Community lyric corrections — submit offset fixes back to LRCLIB
- [ ] Sync lyric offset corrections per track (persist in UserDefaults/file)

---

## P3 — Future / Exploratory

- [ ] iOS companion app (show lyrics on phone while playing on Mac)
- [ ] Translation overlay (show translated lyrics below original)
- [ ] AI-powered lyrics search for tracks not in any database
- [ ] Spotify streaming integration via official Web API (would need OAuth flow)
- [ ] Accessibility: VoiceOver support for lyrics, high-contrast mode

---

## Suggested Release Plan

### v0.1 — "It works" (current state)
What we have. Demo quality.

### v0.2 — "I can actually use this"
Complete P0 items: app bundle, first launch experience, reliable lyrics, overlay polish.
Target: 2 weeks of focused work.

### v0.5 — "I want to keep using this"
Complete P1 items: menu bar improvements, keyboard shortcuts, settings overhaul, performance fixes.
Target: 3-4 weeks after v0.2.

### v1.0 — "I'd recommend this"
Cherry-pick best P2 items (local lyrics, karaoke mode, sharing).
Stable, polished, documented.
Target: 2-3 months from now.

---

## Success Metrics

How to know if yalyric is working as a product:

1. **Lyrics hit rate** — what % of tracks get synced lyrics? Target: >80% for English pop/rock.
2. **Time to first lyric** — how long from song start to lyrics appearing? Target: <2s.
3. **Daily active usage** — does the user keep yalyric running all day? Track via launch-at-login adoption.
4. **GitHub stars / Homebrew installs** — external validation.
5. **Issue reports** — "lyrics wrong for X" means people care enough to report. That's a good sign.
