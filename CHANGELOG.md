# Changelog

## v0.2.2

### Fixed
- Overlay position drift on repeated line changes (track target width instead of in-flight animated frame width)

## v0.2.1

### Fixed
- Overlay position drifting on each line change (anchored center X, immune to animation drift)
- Popover not displaying lyrics (fresh NSTextView/NSScrollView per popover open)
- Auto-hide fading overlay during edit/drag mode
- Concurrent AppleScript execution after timeout (dedicated serial scriptQueue)
- AppConfig key name mismatch causing settings to be silently ignored
- DesktopWidget karaoke mask orphaned after line count change
- Popover resource leak on transient auto-close (NSPopoverDelegate cleanup)
- AppConfig Int/Double getters returning default for explicitly-saved zero values
- Removed karaoke fill from popover (NSTextView can't do smooth per-character updates)
- Ad-hoc codesigning in bundle script for Gatekeeper compatibility
- Homebrew cask postflight removes quarantine automatically

## v0.2.0

### Added
- Apple Music support — auto-detects active player, seamless switching with Spotify
- PlayerBridge architecture — protocol + base class for extensible player integrations
- TOML config file support — `~/.config/yalyric/config.toml` (optional, power users)
- AppConfig centralized configuration layer with typed keys
- Karaoke fill effect — gradient sweep across current line in sync with music
- Parallel provider fetching with scoring (synced + language + line count)
- Shared search validation across all providers (name/artist/duration matching)
- Disk cache for lyrics (~200 tracks, instant replay)
- LRU memory cache (50 tracks)
- Adaptive polling (0.5s playing, 2s idle)
- Dynamic overlay width (resizes to fit text)
- Draggable overlay and widget positioning via menu bar toggle
- Auto-hide overlay when paused
- First launch onboarding message
- AppleScript permission detection with System Settings instructions
- Manual lyric offset (+/- seconds)
- Lyrics source and sync status indicators (overlay, popover, menu bar)
- Podcast/DJ/ad filtering — hides lyrics, shows title in menu bar
- Menu bar: left-click for lyrics popover, right-click for context menu
- Popover: smooth auto-scroll with 5s pause on user scroll
- Desktop widget: configurable line count (3/5/7/9), karaoke fill, crossfade animations
- Musixmatch token persistence (survives restarts)
- Configurable duration tolerance for lyrics matching
- Spotify crash/restart recovery (3s AppleScript timeout)
- Structured logging to ~/Library/Logs/yalyric.log
- App icon

### Fixed
- Wrong-song lyrics from NetEase/LRCLIB (added name/artist validation)
- Duration mismatch causing missing lyrics (Spotify reports inaccurate durations)
- Text jumping left on theme changes (missing NSParagraphStyle in attributedStringValue)
- Overlay repositioning on every theme change (posKey tracking)
- Auto-hide triggered at app launch (dropFirst + hasEverPlayed guard)
- Karaoke fill gradient stale after label swap (removeAnimation on reset)

## v0.1.0

Initial release.

- Spotify track detection via AppleScript
- 4 lyrics sources: LRCLIB, Spotify Internal, Musixmatch, NetEase
- 3 display modes: floating overlay, desktop widget, menu bar
- 5 transition styles: slide up, crossfade, scale fade, push, none
- 6 theme presets with full customization
- Language preference filtering
- SwiftUI settings (General, Appearance, Sources tabs)
- .app bundle, GitHub Actions CI/CD, release workflow
