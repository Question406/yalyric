# Bilingual Lyrics (Original + Chinese Translation) — Design Spec

## Overview

Show a second line of text under the current lyric: a Chinese translation, or a
romaji transliteration, instead of the usual next-line preview. The motivating
case is a Japanese track whose meaning is opaque at a glance, but nothing in the
design is Japanese-specific — it works for any source language NetEase carries a
translation for.

No new dependency, no API key, no machine translation. NetEase already returns
translations; the app currently discards them.

## Why NetEase Is the Whole Feature

`NetEaseProvider.fetchLyrics` requests `?id=X&lv=1` and reads only `json["lrc"]`.
Asking for `&tv=1&rv=1` returns two more timestamped payloads in the same
response:

| Field | Contents |
|---|---|
| `lrc` | Original lyric |
| `tlyric` | Chinese translation, timestamped |
| `romalrc` | Romaji transliteration, timestamped |

Probed against a real Japanese track (2026-09-21): `lrc` had 46 timestamped
non-empty lines, `tlyric` and `romalrc` had 42 each, and **all 42 translation
timestamps matched an original timestamp exactly**. The four unmatched originals
were the credit lines clustered at 0.0–0.64s.

That agreement is what makes this cheap. The two payloads come from one source
and already share a timeline, so pairing needs only a narrow tolerance to absorb
notation differences — not the fuzzy alignment that matching two *different*
providers would demand, where the wrong translation can land under a line.

## User-Visible Behaviour

One setting, `Second line`, with three values:

| Value | Second line shows |
|---|---|
| `Next Line` (default) | The upcoming lyric — today's behaviour, unchanged |
| `Chinese Translation` | `line.translation`, falling back to the next line |
| `Romaji` | `line.romaji`, falling back to the next line |

Fallback is **per line, not per track**: a line NetEase left untranslated shows
the next-line preview rather than a gap.

The overlay keeps its current two-line geometry. The translation occupies the
existing next-line slot; the upcoming-line preview is not shown while a
translation is available.

```
┌────────────────────────────────┐
│                                │
│     original line here         │  24pt, karaoke fill
│     translated line here       │  16pt, 50% opacity
│                                │
└────────────────────────────────┘
```

## Architecture

### Data Model (`Sources/Lyrics/LRCParser.swift`)

`LyricLine` carries its own alternates:

```swift
public struct LyricLine: Equatable, Codable {
    public let time: TimeInterval
    public let text: String
    public let translation: String?   // new
    public let romaji: String?        // new
}
```

Both new fields are optional with defaulted init parameters, so every existing
call site compiles unchanged.

`Lyrics` gains a **non-optional** `schemaVersion: Int`. This is deliberate and
load-bearing — see Cache Invalidation below.

Helper: `Lyrics.hasTranslation` / `Lyrics.hasRomaji`, used by scoring.

### Alignment (`Sources/Lyrics/LyricAlignment.swift`, new)

A pure function, network-free and directly unit-testable:

```swift
static func merge(original: [LyricLine],
                  translation: [LyricLine],
                  romaji: [LyricLine]) -> [LyricLine]
```

Pairing uses a **±50ms tolerance window**, taking the nearest candidate, rather
than matching timestamps for equality. Two reasons:

1. Float equality across two independent parse passes is a trap.
2. `LRCParser`'s centisecond branch treats `[00:21.3]` as 21.03s but
   `[00:21.30]` as 21.30s. An exact key — including an integer-millisecond one —
   would silently drop every line whose notation happened to differ between
   payloads, leaving the user with no translation and no error. Only a tolerance
   window absorbs that.

(An earlier draft of this spec claimed integer-millisecond keying solved point 2.
It does not: 21030 and 21300 are still different keys. Corrected during
implementation.)

Two guards: a translation whose text is identical to the original is dropped
(nothing to show), and an empty-but-present `tlyric` is treated as absent.

### Provider (`Sources/Lyrics/Providers/NetEaseProvider.swift`)

Request `&tv=1&rv=1`; parse `lrc`, `tlyric` and `romalrc` through the existing
`LRCParser`; hand all three to `LyricAlignment.merge`. Unchanged otherwise —
same search, same scoring, same rejection path.

### Scoring (`Sources/Lyrics/LyricsManager.swift`)

`scoreLyrics` gains `hasTranslation +2`, applied **only** when the setting is not
`Next Line`. Ranking is bit-identical when the feature is off.

**The cancellation trap.** `maxScore` is `5`, and the fetch loop does:

```swift
if score >= Self.maxScore { group.cancelAll(); break }
```

A synced LRCLIB result with a language match and more than five lines scores
exactly 5. So on a typical Japanese track, LRCLIB wins the race and cancels
NetEase *before it answers*. Adding the bonus without raising `maxScore` leaves
the feature doing nothing, intermittently, in a way that reads as a network
flake.

`maxScore` therefore becomes a function of the setting: 5 when off, 7 when on.
This gets a dedicated regression test.

### Cache Invalidation

A NetEase track cached before this ships has no translation, and `loadFromDisk`
short-circuits the fetch permanently. The user would switch the setting on and
see nothing on exactly the songs they play most.

`Lyrics.schemaVersion` is non-optional precisely so old JSON **fails to decode**.
`loadFromDisk` already wraps the decode in `try?`, so a failure yields `nil` and
the track refetches once. The migration is the decode failure. A test pins this,
since making the field optional later would silently reintroduce the bug.

Memory cache is process-local and needs no handling.

A second staleness path turned up during implementation, which `schemaVersion`
does not cover: the winning provider now depends on the second-line setting, so
a track cached under `Next Line` would keep serving its untranslated result after
the user switches to `Chinese Translation` — for every track already played.
`LyricsManager.cacheKey` therefore folds the mode into the key, and the default
mode deliberately keys on the bare track ID so existing caches survive untouched
for anyone who never turns this on.

Note this is a pre-existing bug for `lyricsLanguage`, which has the same
dependency and no such handling; `clearCache()` exists but is called from
nowhere. Out of scope here.

### Sync (`Sources/Sync/SyncEngine.swift`)

One new `@Published var secondaryLine: String`, resolved per line against a
`secondaryContent: SecondaryLine` property. The mode is assigned by
`AppDelegate`, not read from `AppConfig` inside the engine — this keeps the
0.5s-cadence sync path free of defaults lookups and keeps resolution unit
testable. `nextLine` stays published and unchanged.

### Display (`Sources/App/AppDelegate.swift`)

```swift
forEachOverlay { $0.updateLyrics(current: currentLine, next: secondaryLine) }
```

**`OverlayWindow` requires no structural change** — no new label, no
`OverlayLayout` change, nothing touching the A/B transition pattern or the
karaoke gradient mask. `resizeToFit` already measures both lines, so a long
Chinese line resizes the pill correctly for free.

### Settings

- `AppConfig.General.secondaryLine`, `Key<String>`, default `"Next Line"`.
- One picker in `SettingsView` → General.

## Data Flow

```
NetEaseProvider.fetchLyrics
    ↓ lrc + tlyric + romalrc → LRCParser (×3)
LyricAlignment.merge (±50ms nearest match)
    ↓ [LyricLine] carrying translation/romaji
LyricsManager (hasTranslation +2, maxScore 5→7)
    ↓ $currentLyrics
SyncEngine.secondaryLine (per-line fallback)
    ↓
AppDelegate → OverlayWindow.updateLyrics(current:next:)
```

## Testing

New:

- **Alignment** — credit lines correctly get `nil`; `[00:21.3]` vs `[00:21.30]`
  pairing; identical-text translations dropped; empty `tlyric` treated as absent.
- **Scoring** — translated NetEase outranks untranslated LRCLIB when on; ranking
  unchanged when off.
- **`maxScore` regression** — the threshold must exceed a perfect untranslated
  score when the setting is on, so `cancelAll` cannot pre-empt NetEase.
- **Cache schema** — JSON without `schemaVersion` fails to decode.
- **SyncEngine** — each mode resolves correctly; per-line fallback when
  `translation` is `nil`.

All test fixtures use invented placeholder text, not real lyrics.

The existing 140 tests stay green; `LyricLine`'s new parameters are defaulted
specifically so none of them need editing.

## Non-Goals

- **Cross-provider merge** (best original from LRCLIB + translation from NetEase).
  Providers disagree on offsets and line splits, so alignment becomes fuzzy, and
  a mis-pairing shows the *wrong* translation under a line — worse than showing
  none.
- **Machine translation.** Apple's `Translation` framework needs macOS 15; the
  deployment target is macOS 13. It would be inert for Ventura and Sonoma users,
  and MT quality on lyrics is poor.
- **Desktop widget.** Interleaving translations would silently halve the
  user-configured `widgetLineCount`. Deliberate boundary, deserves its own
  decision.
- **Menu bar.** Single-line by nature.
- Kugou translations; per-song overrides; a separate `translationOpacity` theme
  knob (reuse `nextLineOpacity` until it has been looked at in situ).
