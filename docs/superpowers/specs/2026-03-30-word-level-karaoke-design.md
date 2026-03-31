# Word-Level Karaoke Design

**Date:** 2026-03-30
**Status:** Draft

## Problem

The current karaoke fill animates a single gradient sweep across the entire current line. This looks okay but lacks the precision of real karaoke apps that highlight each word as it's sung.

## Goal

Per-word karaoke fill: each word in the current line gets its own gradient mask that fills independently based on word-level timing data. When exact timing data isn't available, estimate word timings proportionally.

## Design Decisions

- **Approach A (per-word labels):** Replace single current-line label with a horizontal stack of per-word NSTextField labels, each with its own CAGradientLayer mask.
- **Musixmatch richsync** as the primary word-timing source. The existing `macro.subtitles.get` call already uses `namespace: "lyrics_richsynced"` — richsync data may already be present in the response under `track.richsync.get`.
- **Proportional estimation fallback** when richsync unavailable: distribute line duration across words proportional to character count.
- **Applies to:** OverlayWindow and DesktopWidget (highlight line only). Menu bar popover keeps line-level (intentionally no karaoke fill).
- **Same settings:** Reuses existing `karaokeFillEnabled` and `fillEdgeWidth` — no new user-facing config.

## Architecture

### 1. Data Model Changes

**File:** `Sources/Lyrics/LRCParser.swift`

```swift
struct WordTiming: Equatable, Codable {
    let text: String      // e.g., "Hello " (includes trailing space if present)
    let offset: Double    // seconds from line start
}
```

Add optional `words` field to `LyricLine`:

```swift
struct LyricLine: Equatable, Codable {
    let time: TimeInterval
    let text: String
    let words: [WordTiming]?  // nil = no word data available
}
```

When `words` is nil, consumers use estimated timings. When non-nil, exact Musixmatch richsync timings.

### 2. Musixmatch Richsync Parsing

**File:** `Sources/Lyrics/Providers/MusixmatchProvider.swift`

The existing `macro.subtitles.get` call already includes `namespace: "lyrics_richsynced"`. The macro response may contain a `track.richsync.get` key alongside `track.subtitles.get`.

**Richsync response format** (the `richsync_body` is a JSON string):
```json
[
  {
    "ts": 0.96,
    "te": 3.45,
    "l": [
      { "c": "One, ", "o": 0.0 },
      { "c": "two, ", "o": 0.5 },
      { "c": "three, ", "o": 1.0 }
    ]
  }
]
```

- `ts` / `te` = line start/end time in seconds
- `l[].c` = word text (may include trailing whitespace/punctuation)
- `l[].o` = word offset from line start in seconds

**Parsing priority in `parseResponse`:**
1. Try `track.richsync.get` → parse into `[LyricLine]` with `words` populated
2. Fall back to `track.subtitles.get` → existing LRC parsing, `words` = nil
3. Fall back to `track.lyrics.get` → plain lyrics, `words` = nil

If richsync is not present in the macro response, add a separate `track.richsync.get` call using `commontrack_id` extracted from `matcher.track.get`. Same token auth.

### 3. SyncEngine — Word Progress Calculation

**File:** `Sources/Sync/SyncEngine.swift`

New published property:
```swift
@Published var wordProgresses: [Double] = []
```

On each `update(position:)`:

1. Get the current line's words (from `words` field or estimate)
2. For each word, compute its individual progress (0.0–1.0)
3. A word's progress = `clamp((adjustedPosition - wordStart) / wordDuration, 0, 1)`
4. Where `wordStart = lineStart + word.offset` and `wordDuration = nextWord.offset - word.offset` (last word extends to line end)

**Estimation** (when `words` is nil):
```swift
static func estimateWordTimings(text: String, lineDuration: Double) -> [WordTiming]
```
- Split text on whitespace
- Distribute duration proportional to character count
- Return `[WordTiming]` with calculated offsets
- Cache per-line to avoid recomputation every tick

### 4. WordStackView (New, Shared Component)

**File:** `Sources/Display/WordStackView.swift`

A reusable `NSView` subclass containing a horizontal `NSStackView` of per-word `NSTextField` labels, each with its own `CAGradientLayer` mask.

```swift
class WordStackView: NSView {
    private var wordLabels: [NSTextField] = []
    private var wordMasks: [CAGradientLayer] = []
    private let stackView = NSStackView()

    func setWords(_ words: [String], font: NSFont, textColor: NSColor, letterSpacing: CGFloat, shadow: NSShadow?)
    func updateProgresses(_ progresses: [Double], fillEdgeWidth: CGFloat, animated: Bool)
    func clearMasks()
    var intrinsicTextWidth: CGFloat { get }
}
```

- `setWords()`: Removes existing labels, creates one `NSTextField` per word, applies theme styling, creates gradient masks if karaoke fill is enabled.
- `updateProgresses()`: For each word, animates its gradient mask locations. Same 4-stop pattern and 0.5s CABasicAnimation as current line-level fill.
- `clearMasks()`: Removes all gradient masks (when karaoke disabled).
- `intrinsicTextWidth`: Sum of all word label widths — used by OverlayWindow's `resizeToFit`.

Layout: `NSStackView` with horizontal orientation, spacing 0 (whitespace is included in word text), centered alignment.

### 5. OverlayWindow Changes

**File:** `Sources/Display/OverlayWindow.swift`

Replace:
- `currentLabelA: NSTextField` → `wordStackA: WordStackView`
- `currentLabelB: NSTextField` → `wordStackB: WordStackView`

**On line change (`updateLyrics`):**
1. Get word list from the incoming line (split from text or from `WordTiming.text`)
2. Call `incomingStack.setWords(words, font:, textColor:, ...)`
3. Run existing A/B transition animation on the word stacks (same slide up / crossfade / scale fade / push)
4. Reset incoming stack masks to unfilled

**On progress update:**
- New method: `updateWordProgresses(_ progresses: [Double])`
- Calls `activeStack.updateProgresses(progresses, ...)`

**`resizeToFit` update:** Use `activeStack.intrinsicTextWidth` instead of measuring a single label's text.

**When karaoke disabled:** `WordStackView.setWords()` still creates the labels but skips gradient masks. Visually identical to a single label.

### 6. DesktopWidget Changes

**File:** `Sources/Display/DesktopWidget.swift`

Replace the highlight label (at `currentHighlightIndex`) with a `WordStackView`. The other line labels remain plain `NSTextField`s.

On line change: rebuild the word stack for the highlight line.
On progress update: animate the highlight word stack.

### 7. AppDelegate Changes

**File:** `Sources/App/AppDelegate.swift`

In `updateAllDisplays()`, pass word progresses to displays:
```swift
let wordProgresses = syncEngine.wordProgresses
forEachOverlay { $0.updateWordProgresses(wordProgresses) }
// Widget highlight line gets same progresses
forEachWidget { $0.updateWordProgresses(wordProgresses) }
```

SyncEngine also publishes the current word texts for display:
```swift
@Published var currentWords: [String] = []  // e.g., ["Hello ", "world ", "tonight"]
```

Updated on each line change. AppDelegate passes these to displays via updated `updateLyrics` signature:
```swift
// OverlayWindow
func updateLyrics(current: String, next: String, words: [String])

// DesktopWidget
func updateLyrics(lines: [LyricLine], currentIndex: Int, words: [String])
```

When `words` is empty (karaoke disabled or no lyrics), displays fall back to rendering the full `current` string as a single label — preserving existing behavior.

## Files Summary

| File | Action | Change |
|------|--------|--------|
| `Sources/Lyrics/LRCParser.swift` | Modify | Add `WordTiming` struct, optional `words` on `LyricLine` |
| `Sources/Lyrics/Providers/MusixmatchProvider.swift` | Modify | Parse richsync response, populate `words` field |
| `Sources/Sync/SyncEngine.swift` | Modify | Add `wordProgresses`, estimation, per-word progress calc |
| `Sources/Display/WordStackView.swift` | Create | Shared per-word label stack with gradient masks |
| `Sources/Display/OverlayWindow.swift` | Modify | Replace single labels with WordStackViews |
| `Sources/Display/DesktopWidget.swift` | Modify | Replace highlight label with WordStackView |
| `Sources/App/AppDelegate.swift` | Modify | Pass word progresses and word texts to displays |

## Verification

1. **Richsync available:** Play a popular song → words fill individually with correct timing
2. **No richsync (estimation):** Play a song only on LRCLIB → words fill proportionally, looks smooth
3. **Karaoke disabled:** Toggle off → words display normally without gradient masks
4. **Transitions:** Line changes use existing A/B animations on word stacks
5. **Dynamic width:** Overlay resizes to fit word stack width
6. **DesktopWidget:** Highlight line shows per-word fill, other lines unchanged
7. **Theme changes:** Font/color/edge width changes apply to word labels correctly
8. **Fallback:** If Musixmatch richsync endpoint fails, falls back to line-level lyrics with estimated word timing
