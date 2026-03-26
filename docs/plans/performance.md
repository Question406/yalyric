# yalyric — Performance Plan

## Fixed

### AppleScript on main thread (was HIGH)
**Fixed in this commit.** Moved `NSAppleScript.executeAndReturnError()` to a dedicated serial background queue (`com.yalyric.spotify-poll`). Results are dispatched back to main thread for UI updates. The main thread is no longer blocked during IPC with Spotify.

### Script recompiled every poll (was MEDIUM)
**Fixed in this commit.** AppleScript is now compiled once at static init time and reused on every poll. Previously compiled from source string every 0.5 seconds.

---

## Remaining (not yet fixed)

### 3. Unbounded lyrics cache (LOW-MEDIUM)
**File:** `Sources/Lyrics/LyricsManager.swift`
**Issue:** `cache: [String: Lyrics]` grows forever. In an 8+ hour session, hundreds of entries accumulate.
**Fix:** Add LRU eviction — when count > 50, drop the oldest entry. Simple approach: use an ordered dictionary or track insertion order in a separate array.
**Effort:** ~15 lines of code.

### 4. Redundant UI updates every 0.5s (LOW)
**File:** `Sources/App/AppDelegate.swift:110-116`
**Issue:** `spotifyBridge.$playbackPosition.sink` fires every 0.5s and calls `updateAllDisplays()` even when the current lyric line hasn't changed. Most polls don't change the line — position moves from e.g. 45.2s to 45.7s within the same line.
**Fix:** In `updateAllDisplays()`, compare `syncEngine.currentLineIndex` against a `lastDisplayedLineIndex` stored in AppDelegate. Skip all display updates if the index hasn't changed and we're in the normal lyrics state (not loading/intro/error).
**Effort:** ~5 lines of code.

### 5. orderedProviders reads UserDefaults every fetch (NEGLIGIBLE)
**File:** `Sources/Lyrics/LyricsManager.swift:17-21`
**Issue:** `orderedProviders` computed property reads from UserDefaults on every lyrics fetch.
**Fix:** Cache the ordered list; update when settings change via NotificationCenter.
**Not worth fixing** — UserDefaults reads are in-process and cached by the OS. This fires once per track change, not per poll.

### 6. Language detection per provider result (NEGLIGIBLE)
**File:** `Sources/Lyrics/LyricsManager.swift:53-58`
**Issue:** `NLLanguageRecognizer.processString()` runs on first 10 lines of lyrics for each provider result.
**Not worth fixing** — runs at most 4 times per track change. NLLanguageRecognizer is designed for this scale.

### 7. NSVisualEffectView compositing (NEGLIGIBLE)
**File:** `Sources/Display/OverlayWindow.swift`
**Issue:** Frosted glass background uses GPU compositor for real-time blur.
**Not worth fixing** — macOS handles this natively. Only relevant on very old hardware.
