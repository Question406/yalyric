# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
swift build && .build/debug/yalyric     # Build and run
swift build -c release                   # Release build
./scripts/bundle.sh 0.3.0               # Local .app bundle → dist/ (NOT for publishing — see Releasing)
swift test                               # Run all 140 tests (requires Xcode: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer)
```

The app appears as a music note icon in the menu bar. Needs Spotify desktop app running.

## Releasing

**Tag and push. That is the entire release.** Do not build, upload, or edit the cask
by hand — three workflows in `.github/workflows/` already do it:

```bash
git tag -a v0.3.0 -m "v0.3.0" && git push origin v0.3.0
```

- **`ci.yml`** — build + test on every push to `main` and every PR.
- **`release.yml`** — on a `v*` tag: runs `scripts/bundle.sh` on `macos-14` and
  uploads `dist/yalyric-*.zip` via `softprops/action-gh-release`.
- **`homebrew.yml`** — on Release success: downloads that zip, recomputes its
  sha256, regenerates `Casks/yalyric.rb` and pushes to `Question406/homebrew-tap`.

Check both ran with `gh run list`. Then `brew update && brew upgrade --cask yalyric`.

The version string lives only in the tag, `bundle.sh`'s argument, and the cask.
There is no version constant in `Sources/` to bump.

### Release Gotchas

- **`scripts/bundle.sh` is for local testing, not publishing.** Running it to cut a
  release races `release.yml`, which rebuilds on `macos-14` and overwrites the
  asset. The two zips are never byte-identical — the ad-hoc signature differs per
  build — so a hand-uploaded artifact gets silently replaced by CI's, and anything
  you derived from its sha256 is then stale.

- **The cask is generated, not edited.** It comes from the heredoc in
  `homebrew.yml`. Editing `Casks/yalyric.rb` in the tap directly works until the
  next release regenerates it; change the heredoc instead.

- **Custom release notes must be written after the run finishes.**
  `generate_release_notes: true` is set, but the action does not overwrite a body
  that already exists. Use `gh release edit vX.Y.Z --notes-file notes.md`.

- **The cask's Homebrew deprecations are deliberate.** Homebrew 7.0.1 warns that
  `postflight` and `depends_on macos: ">= :ventura"` are deprecated, but
  `postflight_steps` cannot see `appdir` — `InstallStepsContext` in
  `cask_artifact.rb` exposes only `staged_path`, `caskroom_path`, `home` and
  `config`. Naively "fixing" the warning breaks the install with
  `undefined local variable or method 'appdir'`, which leaves the app quarantined.

- **Builds are ad-hoc signed, never notarized.** Homebrew warns "yalyric's signer
  changed" on every upgrade, and macOS may re-prompt for Apple Events access to
  Spotify. Installing outside Homebrew needs `xattr -cr`.

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

- **LyricsManager**: Queries all 5 providers concurrently via `withTaskGroup`. Scoring: synced(+3), langMatch(+1), lines>5(+1). Early return on perfect score. Two-tier cache: LRU memory (50) + disk JSON (200).

- **SearchMatchScore** (in `LyricsProvider.swift`): Shared validation for search-based providers. Scores name(+3), artist(+3), duration(+2). Minimum score 3 required. All providers must use this for result validation.

- **ThemeManager**: Singleton with `@Published var theme`. Changes debounced 0.3s before UserDefaults save. Display modes subscribe via Combine. 6 presets. Karaoke fill settings preserved across preset switches.

- **OverlayWindow**: Dual A/B label pattern for transitions. CAGradientLayer mask for karaoke fill with CABasicAnimation interpolation. Dynamic width (resizes to fit text, centered). Position changes only when position-related theme properties change (posKey tracking).

### Important Gotchas

- **NSAnimationContext vs CATransaction**: Use NSAnimationContext for AppKit `animator()` proxy properties. Use CATransaction for CALayer properties (transforms, gradient locations). They can run concurrently.
- **`animator()` crashes in global event monitors**: Use `allowsImplicitAnimation` or timers instead of `animator()` in `NSEvent.addGlobalMonitorForEvents` callbacks.
- **`attributedStringValue` overrides label alignment**: Always include `NSParagraphStyle` with `.center` when setting `attributedStringValue` on labels.
- **`NSWindow.alphaValue` needs `animator()`**: `allowsImplicitAnimation` does NOT animate window-level `alphaValue`. Must use `window.animator().alphaValue`.
- **Desktop-level windows can't receive drags**: Temporarily raise to `.floating` level during edit mode.
- **Overlay labels must have compression resistance below 500**: NSWindow imposes its frame at `windowSizeStayPut` priority (500). A label's default 750 outranks it, so the previous line left in the faded-out A/B label held the window at the old width while the origin moved — the overlay grew to the right and sat off centre, and long lines pushed the window past `overlayWidth`. `configureLabel` sets `.defaultLow`; keep it that way.
- **Never animate the overlay frame with `animator().setFrame`**: overlapping NSWindow frame animations don't compose (one target's origin with another's width). `OverlayWindow` uses `FrameAnimator`, which restarts from the current frame on every retarget and is cancelled before any direct `setFrame`.
- **Overlay layout math lives in `OverlayLayout`**: width, vertical centring, karaoke mask rect and frame resolution are pure functions with tests. `init`, `applyPosition` and `moveToScreen` all go through `resolvedFrame`; don't add a fourth copy.
- **Theme changes cascade**: Setting `ThemeManager.shared.theme` triggers Combine → applyTheme on all displays → can rebuild backgrounds. Avoid in hot paths. Use `isLocking` flags when saving position.
- **Musixmatch is refused, not broken**: `token.get` answers HTTP 200 / `status_code: 200` with a `user_token` of 56 zeros — a denial sentinel. `isUsableToken` rejects it so the provider fails fast instead of caching it and matching 'NOKIA' by 'Drake' on every track. A real token needs an un-gated IP; the public alternative is the licensed `api.musixmatch.com` (synced lyrics are a paid tier).

- **Spotify internal provider is dead**: `open.spotify.com/get_access_token` returns 403 URL Blocked; `/api/token` returns 400 "not permitted under the Spotify Developer Terms". There is no official lyrics endpoint. Left in place but it can never succeed.

- **Provider sessions must not carry cookies**: `providerSession` disables cookies deliberately. NetEase throttles callers that return its `NMTID` cookie by ignoring the POST body and answering HTTP 200 with ten arbitrary popular songs — indistinguishable from a real miss.

- **Kugou throttles per keyword**: repeated searches for the same keyword start returning `total: 0`. Queries are capped at two per track for this reason. Kugou is a supplementary CJK source, not a primary one.

- **Provider units differ**: Spotify duration is ms, Apple Music and Kugou are seconds, LRCLIB is seconds, NetEase is ms. `SearchMatchScore` expects **milliseconds**.

- **Traditional vs Simplified Han**: Spotify reports 執迷不悔, NetEase/Kugou report 执迷不悔. `TitleNormalizer.matchKey` applies the `Hant-Hans` transform — without it identical tracks score zero on name.

## Logging

Use `YalyricLog.info()` / `.error()` instead of `print()`. Writes to `~/Library/Logs/yalyric.log` + console. All log lines prefixed `[yalyric]`.

## Testing

Tests are in `Tests/` — 15 files, 140 tests. Key areas:
- `SyncEngineTests`: timestamp matching, offset, progress calculation
- `LyricsModelTests`: binary search, lyrics scoring
- `ThemeTests`: equality, gradient location math
- `LRCParserTests`: LRC format parsing (time tags, plain text, edge cases)
- `TrackInfoTests`: Spotify ID extraction
- `LyricsMatchingTests`: title normalization + search-result scoring (regression cases drawn from real log failures)
- `KugouProviderTests`: LRC payload decoding, candidate selection (seconds→ms unit conversion)
- `ProviderRegistryTests`: merging a persisted providerOrder with newly shipped providers
- `OverlayLayoutTests` / `OverlayWindowTests` / `FrameAnimatorTests`: overlay width, truncation, vertical centring, frame resolution, and the window staying centred when a shorter line follows a longer one
- `OverlayPositionSelectionTests`: choosing a preset clears the dragged position before the theme publishes
