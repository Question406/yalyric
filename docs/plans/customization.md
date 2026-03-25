# yalyric — Customization & Visual Features

> Everything a user should be able to tweak, plus creative visual ideas.

---

## 1. Typography

### Font Selection
- [ ] System font picker — any installed font (SF Pro, Helvetica Neue, Menlo, custom fonts)
- [ ] Separate font for current line vs. next line (e.g., bold serif for current, light sans for next)
- [ ] Font weight picker: ultralight → black (not just regular/bold)
- [ ] Letter spacing (tracking) slider — loose tracking looks great for overlay lyrics
- [ ] Line height control — tighter or looser vertical rhythm

### Font Size
- [ ] Independent size for current line, next line, and widget lines
- [ ] Auto-size mode — shrink font to fit long lines instead of truncating
- [ ] Pinch-to-zoom on overlay to resize (when in edit mode)

---

## 2. Text Effects & Animation

### Transition Styles (user picks one)
- [ ] **Slide up + crossfade** — current default, smooth upward flow
- [ ] **Crossfade only** — simple opacity dissolve, no movement
- [ ] **Typewriter** — letters appear one by one left-to-right within the line duration
- [ ] **Blur dissolve** — old line blurs out while new line sharpens in (gaussian blur animation)
- [ ] **Scale fade** — old line shrinks slightly + fades, new line grows from 95% to 100% + fades in
- [ ] **Push** — old line gets pushed up/left by new line sliding in from below/right
- [ ] **None** — instant swap, no animation (for minimal CPU)

### Text Styling
- [ ] Text color picker (solid color)
- [ ] Gradient text — two-color gradient fill across the lyric line (e.g., blue → purple)
- [ ] Text outline/stroke — adjustable width and color (great for readability on any background)
- [ ] Text shadow — color, blur radius, offset (currently hardcoded black shadow)
- [ ] Glow effect — soft colored glow behind text (neon sign look)
- [ ] Opacity slider for current line and next line independently

### Karaoke Effects
- [ ] **Line fill** — a colored highlight sweeps across the current line in sync with the song progress (like karaoke bars). Uses the `progress` value from SyncEngine.
- [ ] **Word highlight** — if word-level timestamps are available (Spotify API provides these), highlight each word as it's sung
- [ ] **Bounce** — current line does a subtle scale bounce (102% → 100%) when it first appears

---

## 3. Overlay Position & Layout

### Positioning
- [ ] **Drag to reposition** — hold Option key (or click a lock/unlock toggle in menu bar) to enter edit mode. Overlay becomes draggable with a visible border. Release to lock.
- [ ] **Snap to edges** — when dragging near screen edges or center, snap to alignment guides
- [ ] **Preset positions** — top center, bottom center, center, bottom-left, bottom-right (quick pick in settings)
- [ ] **Per-monitor position** — remember different positions for different displays
- [ ] **Save & restore** — position persists across app restarts

### Layout Options
- [ ] **Show 1 line / 2 lines / 3 lines** — configurable visible line count for overlay
- [ ] **Horizontal alignment** — left / center / right
- [ ] **Overlay width** — auto (fit text) or fixed width (e.g., 60% of screen)
- [ ] **Padding** — inner padding around text
- [ ] **Margin from screen edge** — when using preset positions

---

## 4. Background & Container

### Overlay Background
- [ ] **None (transparent)** — current default, text floats on desktop
- [ ] **Pill/rounded rect** — semi-transparent background behind text. Adjustable:
  - Corner radius
  - Background color + opacity
  - Blur (vibrancy) — use NSVisualEffectView for native macOS frosted glass
- [ ] **Full-width bar** — thin strip across the screen width (like a subtitle bar)
- [ ] **Album art blur** — fetch album art, blur it heavily, use as overlay background

### Vibrancy Styles (macOS native)
- [ ] `.hudWindow` — dark translucent (like volume overlay)
- [ ] `.popover` — light translucent
- [ ] `.sidebar` — sidebar style
- [ ] `.underWindowBackground` — subtle, blends with desktop
- [ ] Custom tint color over vibrancy

---

## 5. Color & Theming

### Color Modes
- [ ] **Fixed color** — user picks a color, it stays
- [ ] **Adaptive** — detect underlying screen content brightness, auto-switch white/black text
- [ ] **Album art sync** — extract dominant/vibrant color from current album art (via Core Image), use as text color or glow color. Changes per song.
- [ ] **Time-of-day** — warm tones at night, cool tones during day (sync with system appearance)
- [ ] **Match system accent color** — use macOS accent color setting

### Presets / Themes
- [ ] Ship 5-6 built-in themes:
  - **Classic** — white text, black shadow, no background (default)
  - **Neon** — colored glow, dark background pill
  - **Minimal** — small light gray text, bottom-left corner
  - **Karaoke** — large text, center screen, line fill effect
  - **Spotify** — green accent, dark background, matches Spotify's own style
  - **Terminal** — monospace font, green on black, typewriter effect
- [ ] Import/export theme as JSON
- [ ] Community themes (future: GitHub repo of themes)

---

## 6. Behavior & Intelligence

### Auto-hide Rules
- [ ] Hide when Spotify is paused (configurable delay: immediately / after 5s / after 30s)
- [ ] Hide when Spotify is not running
- [ ] Hide when no lyrics found
- [ ] Hide during instrumental sections (detect gaps >10s between lyric lines)
- [ ] Hide when a fullscreen app is focused (e.g., during presentations, games)
- [ ] Hide when screen is shared (detect screen recording/sharing)
- [ ] Fade out gradually instead of disappearing instantly

### Smart Positioning
- [ ] Avoid covering the mouse cursor area
- [ ] Avoid covering the focused window's title bar
- [ ] "Cinema mode" — when a video player is fullscreen, move lyrics to bottom like subtitles

### Idle Behavior
- [ ] When Spotify is idle for >1 min, show a subtle clock, now-playing info, or nothing
- [ ] Optional: show "last played" info in menu bar when paused

---

## 7. Desktop Widget Customization

- [ ] Number of visible lines: 3 / 5 / 7 / 9
- [ ] Widget size: small / medium / large
- [ ] Background: transparent, blurred card, solid color, album art
- [ ] Current line highlight: bold, color change, underline, scale
- [ ] Past lines: dim, strikethrough, or hide
- [ ] Drag to reposition (same as overlay)
- [ ] Optional: show track info (title + artist) above lyrics
- [ ] Optional: show album art thumbnail

---

## 8. Menu Bar Customization

- [ ] Choose what to show: icon only, icon + current lyric, current lyric only
- [ ] Max width for lyric text in menu bar (before truncation)
- [ ] Scrolling text animation for long lines (marquee style)
- [ ] Click behavior: popover with lyrics vs. toggle overlay visibility

---

## 9. Accessibility

- [ ] Respect macOS "Reduce Motion" — disable animations, use instant transitions
- [ ] Respect macOS "Increase Contrast" — thicker text outlines, opaque backgrounds
- [ ] High contrast mode — force white-on-black or black-on-white
- [ ] Minimum font size enforcement based on system accessibility settings
- [ ] VoiceOver: announce current lyric line changes

---

## 10. Advanced / Power User

- [ ] **CSS-like styling** — expose a `~/.config/yalyric/style.css` or JSON that controls all visual properties. Power users can customize everything without UI.
- [ ] **Multiple overlays** — show lyrics in two places simultaneously (e.g., overlay on main monitor + widget on secondary)
- [ ] **Lyric offset per track** — save a +/- seconds offset for tracks that are consistently off, keyed by Spotify track ID
- [ ] **AppleScript / Shortcuts integration** — expose current lyric, track info, and controls via macOS Shortcuts app
- [ ] **CLI flags** — `yalyric --theme neon --position bottom-center --font "SF Mono"` for quick customization from terminal

---

## Implementation Priority

For the next sprint, I'd suggest this order:

1. **Drag-to-reposition overlay** — most requested UX gap
2. **Font picker + size controls** — most visible customization
3. **Transition style picker** (3-4 styles) — instant perceived quality boost
4. **Background pill with blur** — makes overlay readable everywhere
5. **Auto-hide when paused/no lyrics** — table stakes behavior
6. **Album art color sync** — the "wow" feature that makes screenshots look great
7. **Built-in themes** — lowers the barrier for people who don't want to tweak settings

Everything else follows naturally from the settings infrastructure these items require.
