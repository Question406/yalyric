# yalyric — Karaoke Fill Effect (Per-Word Fading)

> Apple Music-style text fill that sweeps across the current lyric line as the song plays.

## What It Looks Like

The current line starts dim. A gradient edge sweeps left-to-right, "filling" the text from dim → bright in sync with the music. Like light washing across the words as they're sung.

## Data Availability

| Source | Line timestamps | Word timestamps | Notes |
|---|---|---|---|
| LRCLIB | Yes | No | Line-level sweep only |
| Spotify Internal | Yes | **Yes** | `syllables[]` array with per-word `startTimeMs` |
| Musixmatch | Yes | **Yes** | "richsync" format has per-word timing |
| NetEase | Yes | No | Line-level sweep only |

Spotify's API response includes word-level data we currently ignore:
```json
{
  "lines": [{
    "startTimeMs": "23400",
    "words": "hello world",
    "syllables": [
      {"startTimeMs": "23400", "text": "hello"},
      {"startTimeMs": "23800", "text": "world"}
    ]
  }]
}
```

## Implementation Levels

### Level 1: Line-Level Sweep (Start Here)

**Effort:** ~40 lines, 1-2 files
**Works with:** All providers (only needs line timestamps)

Use `SyncEngine.progress` (already computed, 0.0-1.0 within current line) to drive a `CAGradientLayer` mask on the current line label.

```
Text:     "I wanna hold your hand"
Mask:     [bright bright bright | edge | dim dim dim]
                                ↑ progress = 0.4
```

The gradient has 4 stops: `[white, white, clear, clear]` with a narrow edge. Animate `startPoint`/`endPoint` based on `progress`.

**Implementation sketch:**
1. Add a `CAGradientLayer` as the mask of `currentLabelA.layer` and `currentLabelB.layer`
2. Gradient direction: horizontal left-to-right
3. On each `updateLyrics` call (every 0.5s poll), update gradient positions:
   ```swift
   let p = progress  // 0.0 to 1.0
   gradientMask.locations = [0, NSNumber(value: p), NSNumber(value: p + 0.05), 1]
   ```
4. Colors: `[filledColor, filledColor, unfilledColor, unfilledColor]` where filled is full white and unfilled is ~40% white
5. Disable when `transitionStyle == .none` or user opts out

**Limitation:** Not per-word accurate. A 10-second line with 3 words at 0s/2s/8s would fill linearly, not jumping to each word. Good enough for most music; noticeable on rap.

### Level 2: Word-Level Sweep

**Effort:** ~120 lines, 3-4 files
**Works with:** Spotify Internal, Musixmatch (falls back to Level 1 for others)

**Data changes:**
1. Extend `LyricLine` to optionally hold word timestamps:
   ```swift
   struct WordTiming {
       let startTime: TimeInterval
       let text: String
   }
   struct LyricLine {
       let time: TimeInterval
       let text: String
       let words: [WordTiming]?  // nil = no word-level data
   }
   ```
2. Parse `syllables` array in `SpotifyInternalProvider.parseSpotifyLyrics()`
3. Parse richsync format in `MusixmatchProvider`

**Rendering changes:**
1. Measure the x-position of each word in the rendered text using `NSAttributedString.size()` or `CTLine`
2. Map each word's start time to an x-position fraction (0.0-1.0)
3. At any given playback position, compute which word is active and interpolate the gradient position between word boundaries

**Gradient position calculation:**
```swift
// Find active word
let activeWordIndex = words.lastIndex { $0.startTime <= position }
let wordStart = words[activeWordIndex].startTime
let wordEnd = (activeWordIndex + 1 < words.count) ? words[activeWordIndex + 1].startTime : lineEnd
let wordProgress = (position - wordStart) / (wordEnd - wordStart)

// Map to x-position
let xStart = wordXPositions[activeWordIndex]  // fraction 0-1
let xEnd = wordXPositions[activeWordIndex + 1]
let fillPosition = xStart + (xEnd - xStart) * wordProgress
```

### Level 3: Apple Music Quality

**Effort:** ~300+ lines, custom NSView
**Requires:** Core Text for glyph-level positioning

- Replace `NSTextField` with a custom `NSView` that uses `CTFramesetter` / `CTLine` to render text
- Get exact glyph bounding boxes for per-character fill positioning
- Add a soft glow/blur on the fill edge (gaussian blur on the gradient boundary)
- Smooth interpolation between word boundaries using easing curves
- Handle RTL text, CJK characters, mixed scripts

**Not recommended** unless yalyric becomes a dedicated karaoke app.

## Visual Styling

The fill effect needs two colors:
- **Filled color:** the theme's `textColor` at full opacity (bright)
- **Unfilled color:** the theme's `textColor` at ~35-40% opacity (dim)

These should come from the existing theme, not be hardcoded.

The gradient edge width controls how "soft" the fill looks:
- Narrow edge (2-3% of line width): sharp karaoke bar feel
- Wide edge (8-10%): smooth Apple Music feel

This could be a theme property: `fillEdgeWidth: CGFloat = 0.06`

## Settings Integration

Add to Theme:
```swift
var karaokeFilEnabled: Bool = false
var fillEdgeWidth: CGFloat = 0.06  // 6% of line width
```

Add to Appearance tab:
```
Section("Karaoke Fill") {
    Toggle("Enable line fill effect", isOn: ...)
    if enabled {
        LabeledSlider("Edge softness", ...)
    }
}
```

## SyncEngine Changes

Currently `SyncEngine.progress` is computed but only used for... nothing visible. It's already there waiting for this feature.

For Level 2, SyncEngine would need:
```swift
@Published var wordProgress: Double = 0  // 0-1 within current word
@Published var activeWordIndex: Int = -1
```

## Rollout Plan

1. **Level 1 first** — line-level sweep, all providers, ~40 lines, instant wow factor
2. **Level 2 later** — parse Spotify word timestamps, accurate sweep for Spotify-sourced lyrics
3. **Level 3 never** — unless there's strong demand for a karaoke-specific mode

## Dependencies

- Level 1: No new dependencies. Just `CAGradientLayer` + existing `progress`.
- Level 2: Needs changes to `LyricLine`, `SpotifyInternalProvider`, `SyncEngine`.
- Both levels need the fill to be disabled during track-info display (intro/loading states).
