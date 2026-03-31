# Word-Level Karaoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-word karaoke fill — each word gets its own gradient mask that fills independently, driven by Musixmatch richsync timing or proportional estimation.

**Architecture:** Add `WordTiming` to the data model. Musixmatch provider parses richsync for per-word offsets. SyncEngine computes per-word progress (0–1 each). New `WordStackView` renders a horizontal stack of per-word labels with gradient masks. OverlayWindow and DesktopWidget use WordStackView for the current line.

**Tech Stack:** Swift, AppKit (NSStackView, CAGradientLayer), Combine

**Spec:** `docs/superpowers/specs/2026-03-30-word-level-karaoke-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/Lyrics/LRCParser.swift` | Modify | Add `WordTiming` struct, optional `words` on `LyricLine` |
| `Sources/Lyrics/Providers/MusixmatchProvider.swift` | Modify | Parse richsync response into `[WordTiming]` |
| `Sources/Sync/SyncEngine.swift` | Modify | Add `wordProgresses`, `currentWords`, word timing estimation |
| `Sources/Display/WordStackView.swift` | Create | Shared per-word label stack with gradient masks |
| `Sources/Display/OverlayWindow.swift` | Modify | Replace single labels with WordStackViews |
| `Sources/Display/DesktopWidget.swift` | Modify | Replace highlight label with WordStackView |
| `Sources/App/AppDelegate.swift` | Modify | Pass word progresses and word texts to displays |
| `Tests/WordTimingTests.swift` | Create | Tests for WordTiming, estimation, richsync parsing |

---

### Task 1: Data Model — WordTiming + LyricLine update

**Files:**
- Modify: `Sources/Lyrics/LRCParser.swift`
- Create: `Tests/WordTimingTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/WordTimingTests.swift
import XCTest
@testable import yalyricLib

final class WordTimingTests: XCTestCase {

    // MARK: - WordTiming

    func testWordTimingEquality() {
        let a = WordTiming(text: "Hello ", offset: 0.0)
        let b = WordTiming(text: "Hello ", offset: 0.0)
        XCTAssertEqual(a, b)
    }

    func testWordTimingCodable() throws {
        let word = WordTiming(text: "world", offset: 1.5)
        let data = try JSONEncoder().encode(word)
        let decoded = try JSONDecoder().decode(WordTiming.self, from: data)
        XCTAssertEqual(decoded, word)
    }

    // MARK: - LyricLine with words

    func testLyricLineWithWords() {
        let words = [WordTiming(text: "Hello ", offset: 0.0), WordTiming(text: "world", offset: 0.5)]
        let line = LyricLine(time: 5.0, text: "Hello world", words: words)
        XCTAssertEqual(line.words?.count, 2)
        XCTAssertEqual(line.words?[0].text, "Hello ")
        XCTAssertEqual(line.words?[1].offset, 0.5)
    }

    func testLyricLineWithoutWords() {
        let line = LyricLine(time: 5.0, text: "Hello world")
        XCTAssertNil(line.words)
    }

    func testLyricLineCodableWithWords() throws {
        let words = [WordTiming(text: "Hi ", offset: 0.0), WordTiming(text: "there", offset: 0.3)]
        let line = LyricLine(time: 1.0, text: "Hi there", words: words)
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(LyricLine.self, from: data)
        XCTAssertEqual(decoded.words?.count, 2)
        XCTAssertEqual(decoded.time, 1.0)
    }

    func testLyricLineCodableWithoutWords() throws {
        let line = LyricLine(time: 1.0, text: "Hi there")
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(LyricLine.self, from: data)
        XCTAssertNil(decoded.words)
    }

    // MARK: - Word Timing Estimation

    func testEstimateWordTimings() {
        let words = SyncEngine.estimateWordTimings(text: "I love you", lineDuration: 3.0)
        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(words[0].text, "I")
        XCTAssertEqual(words[0].offset, 0.0, accuracy: 0.01)
        // "I" = 1 char, "love" = 4 chars, "you" = 3 chars, total = 8
        // "I" duration = 3.0 * 1/8 = 0.375
        XCTAssertEqual(words[1].text, "love")
        XCTAssertEqual(words[1].offset, 0.375, accuracy: 0.01)
        // "love" duration = 3.0 * 4/8 = 1.5
        XCTAssertEqual(words[2].text, "you")
        XCTAssertEqual(words[2].offset, 1.875, accuracy: 0.01)
    }

    func testEstimateWordTimingsEmptyString() {
        let words = SyncEngine.estimateWordTimings(text: "", lineDuration: 3.0)
        XCTAssertTrue(words.isEmpty)
    }

    func testEstimateWordTimingsSingleWord() {
        let words = SyncEngine.estimateWordTimings(text: "Hello", lineDuration: 2.0)
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words[0].text, "Hello")
        XCTAssertEqual(words[0].offset, 0.0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WordTimingTests 2>&1 | tail -5`
Expected: Compilation failure — `WordTiming` not found.

- [ ] **Step 3: Add WordTiming struct and update LyricLine**

In `Sources/Lyrics/LRCParser.swift`, add before `LyricLine`:

```swift
public struct WordTiming: Equatable, Codable {
    public let text: String      // word text (may include trailing space)
    public let offset: Double    // seconds from line start

    public init(text: String, offset: Double) {
        self.text = text
        self.offset = offset
    }
}
```

Update `LyricLine` to:

```swift
public struct LyricLine: Equatable, Codable {
    public let time: TimeInterval  // seconds
    public let text: String
    public let words: [WordTiming]?  // nil = no word-level data

    public init(time: TimeInterval, text: String, words: [WordTiming]? = nil) {
        self.time = time
        self.text = text
        self.words = words
    }
}
```

- [ ] **Step 4: Add estimateWordTimings to SyncEngine**

In `Sources/Sync/SyncEngine.swift`, add as a static method:

```swift
/// Estimate word timings by distributing duration proportional to character count.
public static func estimateWordTimings(text: String, lineDuration: Double) -> [WordTiming] {
    let wordTexts = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    guard !wordTexts.isEmpty, lineDuration > 0 else { return [] }

    let totalChars = wordTexts.reduce(0) { $0 + $1.count }
    guard totalChars > 0 else { return [] }

    var offset = 0.0
    return wordTexts.map { word in
        let timing = WordTiming(text: word, offset: offset)
        offset += lineDuration * Double(word.count) / Double(totalChars)
        return timing
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter WordTimingTests 2>&1 | tail -10`
Expected: All 8 tests pass.

- [ ] **Step 6: Run all tests to verify no regressions**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass (existing tests use `LyricLine(time:text:)` which still works due to default `words: nil`).

- [ ] **Step 7: Commit**

```bash
git add Sources/Lyrics/LRCParser.swift Sources/Sync/SyncEngine.swift Tests/WordTimingTests.swift
git commit -m "feat: add WordTiming struct and word timing estimation"
```

---

### Task 2: SyncEngine — word progress calculation

**Files:**
- Modify: `Sources/Sync/SyncEngine.swift`
- Modify: `Tests/WordTimingTests.swift`

- [ ] **Step 1: Write failing tests for word progress**

Append to `Tests/WordTimingTests.swift`:

```swift
// MARK: - SyncEngine Word Progress

@MainActor
final class SyncEngineWordProgressTests: XCTestCase {

    private func makeLyricsWithWords() -> Lyrics {
        Lyrics(lines: [
            LyricLine(time: 0.0, text: "Hello world tonight", words: [
                WordTiming(text: "Hello", offset: 0.0),
                WordTiming(text: "world", offset: 1.0),
                WordTiming(text: "tonight", offset: 2.0),
            ]),
            LyricLine(time: 5.0, text: "Second line"),
        ], source: .musixmatch, isSynced: true)
    }

    func testWordProgressesAtLineStart() {
        let engine = SyncEngine()
        engine.setLyrics(makeLyricsWithWords())
        engine.update(position: 0.0)
        XCTAssertEqual(engine.wordProgresses.count, 3)
        XCTAssertEqual(engine.wordProgresses[0], 0.0, accuracy: 0.01)
        XCTAssertEqual(engine.wordProgresses[1], 0.0, accuracy: 0.01)
        XCTAssertEqual(engine.wordProgresses[2], 0.0, accuracy: 0.01)
    }

    func testWordProgressesMidLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeLyricsWithWords())
        engine.update(position: 1.5)  // halfway through "world" (1.0-2.0)
        XCTAssertEqual(engine.wordProgresses.count, 3)
        XCTAssertEqual(engine.wordProgresses[0], 1.0, accuracy: 0.01)  // "Hello" fully done
        XCTAssertEqual(engine.wordProgresses[1], 0.5, accuracy: 0.01)  // "world" half done
        XCTAssertEqual(engine.wordProgresses[2], 0.0, accuracy: 0.01)  // "tonight" not started
    }

    func testWordProgressesEndOfLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeLyricsWithWords())
        engine.update(position: 4.9)  // near end of line (line ends at 5.0)
        XCTAssertEqual(engine.wordProgresses[0], 1.0, accuracy: 0.01)
        XCTAssertEqual(engine.wordProgresses[1], 1.0, accuracy: 0.01)
        XCTAssertEqual(engine.wordProgresses[2], 1.0, accuracy: 0.1)  // nearly done
    }

    func testWordProgressesEstimated() {
        let engine = SyncEngine()
        // No words field — should estimate
        let lyrics = Lyrics(lines: [
            LyricLine(time: 0.0, text: "AB CD"),
            LyricLine(time: 4.0, text: "Next"),
        ], source: .lrclib, isSynced: true)
        engine.setLyrics(lyrics)
        engine.update(position: 2.0)  // halfway through 4s line
        // "AB" = 2 chars, "CD" = 2 chars, total = 4, each gets 2s
        XCTAssertEqual(engine.wordProgresses.count, 2)
        XCTAssertEqual(engine.wordProgresses[0], 1.0, accuracy: 0.01)  // "AB" done (0-2s)
        XCTAssertEqual(engine.wordProgresses[1], 0.0, accuracy: 0.01)  // "CD" starting (2-4s)
    }

    func testWordProgressesResetOnLineChange() {
        let engine = SyncEngine()
        engine.setLyrics(makeLyricsWithWords())
        engine.update(position: 3.0)
        XCTAssertEqual(engine.wordProgresses.count, 3)
        engine.update(position: 5.5)  // moved to second line
        // Second line has no words, will estimate for "Second line"
        XCTAssertEqual(engine.currentWords.count, 2)
        XCTAssertEqual(engine.currentWords[0], "Second")
    }

    func testCurrentWordsFromWordTimings() {
        let engine = SyncEngine()
        engine.setLyrics(makeLyricsWithWords())
        engine.update(position: 1.0)
        XCTAssertEqual(engine.currentWords, ["Hello", "world", "tonight"])
    }

    func testWordProgressesBeforeFirstLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeLyricsWithWords())
        engine.update(position: -1.0)  // before first line (starts at 0.0... but binary search returns nil)
        XCTAssertTrue(engine.wordProgresses.isEmpty)
        XCTAssertTrue(engine.currentWords.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SyncEngineWordProgressTests 2>&1 | tail -5`
Expected: Compilation failure — `wordProgresses` and `currentWords` not found on SyncEngine.

- [ ] **Step 3: Implement word progress in SyncEngine**

In `Sources/Sync/SyncEngine.swift`, add published properties after `progress`:

```swift
@Published public var wordProgresses: [Double] = []
@Published public var currentWords: [String] = []
```

Add a private cache:

```swift
private var estimatedTimingsCache: (index: Int, timings: [WordTiming])? = nil
```

Update `setLyrics(_:)` to also reset the new properties:

```swift
public func setLyrics(_ lyrics: Lyrics?) {
    self.lyrics = lyrics
    currentLineIndex = -1
    currentLine = ""
    nextLine = ""
    progress = 0
    wordProgresses = []
    currentWords = []
    estimatedTimingsCache = nil
}
```

Add a private method to get word timings for a line:

```swift
private func wordTimings(for index: Int, lineDuration: Double) -> [WordTiming] {
    guard let lyrics = lyrics, index >= 0, index < lyrics.lines.count else { return [] }
    let line = lyrics.lines[index]
    if let words = line.words, !words.isEmpty {
        return words
    }
    // Use cached estimation if same line
    if let cached = estimatedTimingsCache, cached.index == index {
        return cached.timings
    }
    let estimated = Self.estimateWordTimings(text: line.text, lineDuration: lineDuration)
    estimatedTimingsCache = (index: index, timings: estimated)
    return estimated
}
```

Update the end of `update(position:)` — after the existing progress calculation, add word progress computation. Replace the progress calculation section (after `if index != currentLineIndex {` block) with:

```swift
// Calculate progress within current line
let lineStart = lyrics.lines[index].time
let lineEnd = (index + 1 < lyrics.lines.count) ? lyrics.lines[index + 1].time : lyrics.lines[index].time + 5.0
let lineDuration = lineEnd - lineStart
if lineDuration > 0 {
    progress = min(1.0, max(0.0, (adjustedPosition - lineStart) / lineDuration))
}

// Calculate per-word progress
let timings = wordTimings(for: index, lineDuration: lineDuration)
if currentWords.count != timings.count {
    currentWords = timings.map { $0.text }
}
var newProgresses = [Double](repeating: 0, count: timings.count)
let posInLine = adjustedPosition - lineStart
for (i, word) in timings.enumerated() {
    let wordStart = word.offset
    let wordEnd: Double
    if i + 1 < timings.count {
        wordEnd = timings[i + 1].offset
    } else {
        wordEnd = lineDuration
    }
    let wordDuration = wordEnd - wordStart
    if wordDuration > 0 {
        newProgresses[i] = min(1.0, max(0.0, (posInLine - wordStart) / wordDuration))
    } else {
        newProgresses[i] = posInLine >= wordStart ? 1.0 : 0.0
    }
}
wordProgresses = newProgresses
```

Also, in the early returns (before first line, nil lyrics, unsynced), make sure to clear word state:

In the `guard let lyrics = lyrics` early return, add:
```swift
wordProgresses = []
currentWords = []
```

In the `guard lyrics.isSynced` early return, after setting currentLine/nextLine, add:
```swift
wordProgresses = []
currentWords = []
```

In the `guard let index = lyrics.currentLineIndex` early return (before first line), add:
```swift
wordProgresses = []
currentWords = []
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SyncEngineWordProgressTests 2>&1 | tail -10`
Expected: All 7 tests pass.

- [ ] **Step 5: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Sync/SyncEngine.swift Tests/WordTimingTests.swift
git commit -m "feat: add per-word progress calculation to SyncEngine"
```

---

### Task 3: Musixmatch richsync parsing

**Files:**
- Modify: `Sources/Lyrics/Providers/MusixmatchProvider.swift`
- Modify: `Tests/WordTimingTests.swift`

- [ ] **Step 1: Write failing tests for richsync parsing**

Append to `Tests/WordTimingTests.swift`:

```swift
// MARK: - Richsync Parsing

final class RichsyncParsingTests: XCTestCase {

    func testParseRichsyncBody() throws {
        let json = """
        [
            {"ts": 0.96, "te": 3.45, "l": [
                {"c": "One, ", "o": 0.0},
                {"c": "two, ", "o": 0.5},
                {"c": "three", "o": 1.0}
            ]},
            {"ts": 4.0, "te": 7.0, "l": [
                {"c": "Hello ", "o": 0.0},
                {"c": "world", "o": 1.5}
            ]}
        ]
        """
        let lines = RichsyncParser.parse(json)
        XCTAssertEqual(lines.count, 2)

        XCTAssertEqual(lines[0].time, 0.96, accuracy: 0.01)
        XCTAssertEqual(lines[0].text, "One, two, three")
        XCTAssertEqual(lines[0].words?.count, 3)
        XCTAssertEqual(lines[0].words?[0].text, "One, ")
        XCTAssertEqual(lines[0].words?[0].offset, 0.0)
        XCTAssertEqual(lines[0].words?[1].text, "two, ")
        XCTAssertEqual(lines[0].words?[1].offset, 0.5)
        XCTAssertEqual(lines[0].words?[2].text, "three")
        XCTAssertEqual(lines[0].words?[2].offset, 1.0)

        XCTAssertEqual(lines[1].time, 4.0, accuracy: 0.01)
        XCTAssertEqual(lines[1].words?.count, 2)
    }

    func testParseRichsyncBodyInvalid() {
        let lines = RichsyncParser.parse("not json")
        XCTAssertTrue(lines.isEmpty)
    }

    func testParseRichsyncBodyEmpty() {
        let lines = RichsyncParser.parse("[]")
        XCTAssertTrue(lines.isEmpty)
    }

    func testParseRichsyncBodyMissingFields() {
        let json = """
        [{"ts": 1.0}]
        """
        let lines = RichsyncParser.parse(json)
        XCTAssertTrue(lines.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RichsyncParsingTests 2>&1 | tail -5`
Expected: Compilation failure — `RichsyncParser` not found.

- [ ] **Step 3: Add RichsyncParser to MusixmatchProvider**

In `Sources/Lyrics/Providers/MusixmatchProvider.swift`, add at the bottom of the file (outside the struct):

```swift
/// Parses Musixmatch richsync JSON into LyricLines with word-level timing.
enum RichsyncParser {
    static func parse(_ richsyncBody: String) -> [LyricLine] {
        guard let data = richsyncBody.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var lines: [LyricLine] = []
        for entry in entries {
            guard let ts = entry["ts"] as? Double,
                  let wordArray = entry["l"] as? [[String: Any]],
                  !wordArray.isEmpty else {
                continue
            }

            var words: [WordTiming] = []
            var fullText = ""
            for w in wordArray {
                guard let c = w["c"] as? String,
                      let o = w["o"] as? Double else { continue }
                words.append(WordTiming(text: c, offset: o))
                fullText += c
            }

            guard !words.isEmpty else { continue }
            let text = fullText.trimmingCharacters(in: .whitespaces)
            lines.append(LyricLine(time: ts, text: text, words: words))
        }

        return lines.sorted { $0.time < $1.time }
    }
}
```

- [ ] **Step 4: Update parseResponse to try richsync first**

In `MusixmatchProvider.parseResponse`, add richsync parsing before the existing subtitle parsing. After the match validation block (after line 92) and before `// Try synced subtitles first`, add:

```swift
// Try richsync (word-level timing) first
if let richsyncGet = macroCalls["track.richsync.get"] as? [String: Any],
   let rsMessage = richsyncGet["message"] as? [String: Any],
   let rsBody = rsMessage["body"] as? [String: Any],
   let richsyncList = rsBody["richsync_list"] as? [[String: Any]],
   let first = richsyncList.first,
   let richsync = first["richsync"] as? [String: Any],
   let richsyncBody = richsync["richsync_body"] as? String {
    let lines = RichsyncParser.parse(richsyncBody)
    if !lines.isEmpty {
        YalyricLog.info("[musixmatch] Got richsync with \(lines.count) lines, word-level timing available")
        return Lyrics(lines: lines, source: .musixmatch, isSynced: true)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter RichsyncParsingTests 2>&1 | tail -10`
Expected: All 4 tests pass.

- [ ] **Step 6: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Lyrics/Providers/MusixmatchProvider.swift Tests/WordTimingTests.swift
git commit -m "feat: add Musixmatch richsync parsing for word-level timing"
```

---

### Task 4: WordStackView — shared component

**Files:**
- Create: `Sources/Display/WordStackView.swift`

- [ ] **Step 1: Create WordStackView**

```swift
// Sources/Display/WordStackView.swift
import AppKit
import QuartzCore

/// A horizontal stack of per-word NSTextField labels, each with its own gradient mask for karaoke fill.
class WordStackView: NSView {
    private(set) var wordLabels: [NSTextField] = []
    private var wordMasks: [CAGradientLayer] = []
    private let stackView = NSStackView()
    private var karaokeFillEnabled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        stackView.orientation = .horizontal
        stackView.spacing = 0
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Rebuild labels for a new set of words.
    func setWords(
        _ words: [String],
        font: NSFont,
        textColor: NSColor,
        letterSpacing: CGFloat,
        shadow: NSShadow?,
        karaokeFillEnabled: Bool
    ) {
        self.karaokeFillEnabled = karaokeFillEnabled

        // Remove old labels
        for label in wordLabels {
            stackView.removeArrangedSubview(label)
            label.removeFromSuperview()
        }
        wordLabels.removeAll()
        wordMasks.removeAll()

        // Create one label per word
        for word in words {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byClipping
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.wantsLayer = true
            label.translatesAutoresizingMaskIntoConstraints = false

            // Build attributed string
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
            ]
            if letterSpacing != 0 {
                attrs[.kern] = letterSpacing
            }
            label.attributedStringValue = NSAttributedString(string: word, attributes: attrs)
            if let shadow = shadow {
                label.shadow = shadow
            }

            stackView.addArrangedSubview(label)
            wordLabels.append(label)

            // Create gradient mask if karaoke fill enabled
            if karaokeFillEnabled {
                let mask = CAGradientLayer()
                mask.startPoint = CGPoint(x: 0, y: 0.5)
                mask.endPoint = CGPoint(x: 1, y: 0.5)
                mask.colors = [
                    NSColor.white.cgColor,
                    NSColor.white.cgColor,
                    NSColor.white.withAlphaComponent(0.35).cgColor,
                    NSColor.white.withAlphaComponent(0.35).cgColor,
                ]
                mask.locations = [0, 0, 0.001, 1]
                label.layer?.mask = mask
                wordMasks.append(mask)
            }
        }
    }

    /// Sync gradient mask frames to label bounds. Call after layout changes.
    func syncMaskFrames() {
        for (i, label) in wordLabels.enumerated() where i < wordMasks.count {
            wordMasks[i].frame = label.bounds
        }
    }

    /// Update per-word karaoke fill progress.
    func updateProgresses(_ progresses: [Double], fillEdgeWidth: CGFloat, animated: Bool) {
        guard karaokeFillEnabled else { return }

        // Ensure layout is current
        layoutSubtreeIfNeeded()
        syncMaskFrames()

        for (i, mask) in wordMasks.enumerated() {
            let p = Float(i < progresses.count ? min(1, max(0, progresses[i])) : 0)
            let edge = Float(fillEdgeWidth)
            let newLocations: [NSNumber] = [0, NSNumber(value: p), NSNumber(value: p + edge), 1]

            if animated {
                let anim = CABasicAnimation(keyPath: "locations")
                anim.fromValue = mask.presentation()?.locations ?? mask.locations
                anim.toValue = newLocations
                anim.duration = 0.5
                anim.timingFunction = CAMediaTimingFunction(name: .linear)
                anim.isRemovedOnCompletion = false
                anim.fillMode = .forwards

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                mask.locations = newLocations
                CATransaction.commit()
                mask.add(anim, forKey: "karaokeFill")
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                mask.locations = newLocations
                CATransaction.commit()
            }
        }
    }

    /// Reset all word masks to unfilled state.
    func resetMasks(fillEdgeWidth: CGFloat) {
        for mask in wordMasks {
            mask.removeAnimation(forKey: "karaokeFill")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.locations = [0, 0, NSNumber(value: Float(fillEdgeWidth)), 1]
            CATransaction.commit()
        }
    }

    /// Remove all gradient masks.
    func clearMasks() {
        for label in wordLabels {
            label.layer?.mask = nil
        }
        wordMasks.removeAll()
    }

    /// Total width of all word labels — for dynamic sizing.
    var intrinsicTextWidth: CGFloat {
        wordLabels.reduce(0) { sum, label in
            sum + label.intrinsicContentSize.width
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -3`
Expected: Build succeeded.

- [ ] **Step 3: Commit**

```bash
git add Sources/Display/WordStackView.swift
git commit -m "feat: add WordStackView for per-word karaoke labels"
```

---

### Task 5: OverlayWindow — replace labels with WordStackViews

**Files:**
- Modify: `Sources/Display/OverlayWindow.swift`

This is the most complex task. The key changes:
1. Replace `currentLabelA`/`currentLabelB` with `wordStackA`/`wordStackB`
2. Update `setupContent` to use word stacks
3. Update `updateLyrics` to accept words and populate word stacks
4. Add `updateWordProgresses` method
5. Update `applyTheme` for word stacks
6. Update `resizeToFit` to use word stack width
7. Update transition animations to animate word stacks
8. Remove old single-label gradient mask code

- [ ] **Step 1: Replace label properties**

Replace:
```swift
private let currentLabelA = NSTextField(labelWithString: "")
private let currentLabelB = NSTextField(labelWithString: "")
```

With:
```swift
private let wordStackA = WordStackView()
private let wordStackB = WordStackView()
```

Remove these properties (no longer needed — masks are in WordStackView):
```swift
private var gradientMaskA: CAGradientLayer?
private var gradientMaskB: CAGradientLayer?
```

- [ ] **Step 2: Update setupContent**

Replace the label setup for currentLabelA/currentLabelB with word stack setup. Replace lines that configure and add currentLabelA/currentLabelB and their constraints with:

```swift
wordStackA.translatesAutoresizingMaskIntoConstraints = false
wordStackA.alphaValue = 1
wordStackB.translatesAutoresizingMaskIntoConstraints = false
wordStackB.alphaValue = 0

container.addSubview(wordStackA)
container.addSubview(wordStackB)
container.addSubview(nextLyricLabel)
container.addSubview(sourceLabel)

currentTopA = wordStackA.topAnchor.constraint(equalTo: container.topAnchor, constant: 8)
currentTopB = wordStackB.topAnchor.constraint(equalTo: container.topAnchor, constant: 8 + slideDistance)

NSLayoutConstraint.activate([
    wordStackA.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
    wordStackA.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
    currentTopA,

    wordStackB.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
    wordStackB.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
    currentTopB,

    nextLyricLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
    nextLyricLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
    nextLyricLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 44),

    sourceLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
    sourceLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
])
```

- [ ] **Step 3: Update updateLyrics signature and implementation**

Change signature to accept words:

```swift
func updateLyrics(current: String, next: String, words: [String] = []) {
```

In the body, replace references to `currentLabelA`/`currentLabelB` with `wordStackA`/`wordStackB`. The key change is on line change — instead of setting `incomingLabel.stringValue = current`, populate the word stack:

Where the current code does `incomingLabel.stringValue = current`, replace with:

```swift
let theme = ThemeManager.shared.theme
let wordTexts = words.isEmpty ? [current] : words
incomingStack.setWords(
    wordTexts,
    font: theme.currentLineFont,
    textColor: theme.textColor,
    letterSpacing: theme.letterSpacing,
    shadow: theme.textShadow,
    karaokeFillEnabled: theme.karaokeFillEnabled
)
```

Where `incomingStack` = `useA ? wordStackB : wordStackA` (the incoming stack).

Replace `activeLabel` / `incomingLabel` with `activeStack` / `incomingStack` (`useA ? wordStackA : wordStackB` / `useA ? wordStackB : wordStackA`) in all transition animations. The animations work the same — `animator().alphaValue`, constraint changes, etc. — because `WordStackView` is an `NSView`.

For the `stringValue` check that detects line changes, compare against the full text. Add a helper:

```swift
private func currentText(of stack: WordStackView) -> String {
    stack.wordLabels.map { $0.stringValue }.joined()
}
```

Replace `activeLabel.stringValue != current` with `currentText(of: activeStack) != current`.

- [ ] **Step 4: Add updateWordProgresses method**

```swift
func updateWordProgresses(_ progresses: [Double]) {
    let theme = ThemeManager.shared.theme
    guard theme.karaokeFillEnabled else { return }
    let activeStack = useA ? wordStackA : wordStackB
    activeStack.updateProgresses(progresses, fillEdgeWidth: theme.fillEdgeWidth, animated: true)
}
```

- [ ] **Step 5: Update updateProgress to delegate to word stacks**

The existing `updateProgress(_ progress: Double)` method should be kept for backward compat (AppDelegate still calls it for line-level progress). But its gradient mask code should be updated to work with word stacks:

```swift
func updateProgress(_ progress: Double) {
    // Line-level progress is still used when word progresses aren't available
    // Word-level progress is handled by updateWordProgresses
}
```

Actually, simplify: make `updateProgress` a no-op if karaoke is handled at word level. The word-level `updateWordProgresses` replaces it. Keep the method signature for AppDelegate compat but empty the body:

```swift
func updateProgress(_ progress: Double) {
    // Word-level progress handled by updateWordProgresses()
    // This method kept for API compat
}
```

- [ ] **Step 6: Update applyTheme**

In `applyTheme`, replace the label theming for `currentLabelA`/`currentLabelB` with:

```swift
// Re-apply theme to word stacks
for stack in [wordStackA, wordStackB] {
    let wordTexts = stack.wordLabels.map { $0.stringValue }
    if !wordTexts.isEmpty {
        stack.setWords(
            wordTexts,
            font: theme.currentLineFont,
            textColor: theme.textColor,
            letterSpacing: theme.letterSpacing,
            shadow: shadow,
            karaokeFillEnabled: theme.karaokeFillEnabled
        )
    }
}
```

Remove the old `applyKaraokeFill` calls and the `applyKaraokeFill` method (gradient masks are now in WordStackView).

Remove the `setupGradientMask(for:)` method.

- [ ] **Step 7: Update resizeToFit**

Replace the `measureTextWidth` calls with word stack intrinsic width:

```swift
private func resizeToFit(currentText: String, nextText: String, animated: Bool) {
    let theme = ThemeManager.shared.theme
    if theme.backgroundStyle == .bar { return }

    let activeStack = useA ? wordStackA : wordStackB
    let currentWidth = activeStack.intrinsicTextWidth + horizontalPadding * 2
    let nextWidth = measureTextWidth(nextText, font: theme.nextLineFont, letterSpacing: theme.letterSpacing)
    let textWidth = max(currentWidth, nextWidth + horizontalPadding * 2)
    let targetWidth = min(theme.overlayWidth, max(minOverlayWidth, textWidth))

    guard abs(lastTargetWidth - targetWidth) > 2 else { return }
    lastTargetWidth = targetWidth

    let currentY = frame.origin.y
    let newOrigin = NSPoint(x: anchoredCenterX - targetWidth / 2, y: currentY)
    let newFrame = NSRect(origin: newOrigin, size: NSSize(width: targetWidth, height: frame.height))

    if animated {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = theme.animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(newFrame, display: true)
        }
    } else {
        setFrame(newFrame, display: true)
    }
}
```

- [ ] **Step 8: Update resetLabelsToCleanState**

Replace references to `currentLabelA`/`currentLabelB` with `wordStackA`/`wordStackB`:

```swift
private func resetLabelsToCleanState() {
    wordStackA.layer?.removeAllAnimations()
    wordStackB.layer?.removeAllAnimations()

    let restY: CGFloat = 8
    let activeStack = useA ? wordStackA : wordStackB
    let hiddenStack = useA ? wordStackB : wordStackA
    let activeTop = useA ? currentTopA! : currentTopB!
    let hiddenTop = useA ? currentTopB! : currentTopA!

    activeStack.alphaValue = 1
    activeStack.layer?.setAffineTransform(.identity)
    activeTop.constant = restY

    hiddenStack.alphaValue = 0
    hiddenStack.layer?.setAffineTransform(.identity)
    hiddenTop.constant = restY

    contentView?.layoutSubtreeIfNeeded()
    isAnimating = false
}
```

- [ ] **Step 9: Update showTrackInfo**

`showTrackInfo` calls `updateLyrics` — no change needed since the default `words: []` parameter handles it.

- [ ] **Step 10: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeded.

- [ ] **Step 11: Commit**

```bash
git add Sources/Display/OverlayWindow.swift
git commit -m "feat: replace overlay labels with per-word WordStackViews"
```

---

### Task 6: DesktopWidget — word-level fill on highlight line

**Files:**
- Modify: `Sources/Display/DesktopWidget.swift`

- [ ] **Step 1: Add WordStackView property**

Add after `gradientMask` property:

```swift
private var highlightWordStack: WordStackView?
```

- [ ] **Step 2: Update rebuildLabels to use WordStackView for highlight**

In `rebuildLabels()`, replace the highlight label (at `currentHighlightIndex`) with a `WordStackView`. After the existing loop that creates labels, replace the label at the highlight index:

```swift
private func rebuildLabels() {
    // Remove old labels and word stack
    for label in lineLabels {
        stackView.removeArrangedSubview(label)
        label.removeFromSuperview()
    }
    if let ws = highlightWordStack {
        stackView.removeArrangedSubview(ws)
        ws.removeFromSuperview()
    }
    lineLabels.removeAll()
    highlightWordStack = nil
    gradientMask = nil

    for i in 0..<visibleLines {
        if i == currentHighlightIndex {
            // Use WordStackView for the highlight line
            let ws = WordStackView()
            ws.translatesAutoresizingMaskIntoConstraints = false
            highlightWordStack = ws
            lineLabels.append(NSTextField(labelWithString: ""))  // placeholder for index tracking
            stackView.addArrangedSubview(ws)
        } else {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.wantsLayer = true
            lineLabels.append(label)
            stackView.addArrangedSubview(label)
        }
    }
}
```

- [ ] **Step 3: Update updateLyrics to accept words**

Change signature:

```swift
func updateLyrics(lines: [LyricLine], currentIndex: Int, words: [String] = []) {
```

In the body, when updating the highlight line, populate the WordStackView instead of setting stringValue:

```swift
if i == currentHighlightIndex {
    let text = (lineIndex >= 0 && lineIndex < lines.count) ? lines[lineIndex].text : ""
    let wordTexts = (i == currentHighlightIndex) ? (words.isEmpty ? [text] : words) : [text]
    if let ws = highlightWordStack {
        let theme = ThemeManager.shared.theme
        ws.setWords(
            wordTexts.filter { !$0.isEmpty },
            font: theme.currentLineFont,
            textColor: theme.textColor,
            letterSpacing: theme.letterSpacing,
            shadow: theme.textShadow,
            karaokeFillEnabled: theme.karaokeFillEnabled
        )
    }
}
```

For non-highlight lines, keep existing label logic.

- [ ] **Step 4: Add updateWordProgresses method**

```swift
func updateWordProgresses(_ progresses: [Double]) {
    let theme = ThemeManager.shared.theme
    guard theme.karaokeFillEnabled, let ws = highlightWordStack else { return }
    ws.updateProgresses(progresses, fillEdgeWidth: theme.fillEdgeWidth, animated: true)
}
```

- [ ] **Step 5: Update existing updateProgress**

Make it a no-op (word-level replaces it):

```swift
func updateProgress(_ progress: Double) {
    // Word-level progress handled by updateWordProgresses()
}
```

Remove the old `applyKaraokeFill` method and `gradientMask` property usage.

- [ ] **Step 6: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeded.

- [ ] **Step 7: Commit**

```bash
git add Sources/Display/DesktopWidget.swift
git commit -m "feat: add word-level karaoke to DesktopWidget highlight line"
```

---

### Task 7: AppDelegate — wire word progresses to displays

**Files:**
- Modify: `Sources/App/AppDelegate.swift`

- [ ] **Step 1: Pass words and word progresses in updateAllDisplays**

In `updateAllDisplays()`, where lyrics are dispatched to displays, update the calls:

Replace:
```swift
forEachOverlay { $0.updateLyrics(current: currentLine, next: nextLine) }
```
With:
```swift
let currentWords = syncEngine.currentWords
forEachOverlay { $0.updateLyrics(current: currentLine, next: nextLine, words: currentWords) }
```

Replace:
```swift
forEachOverlay { $0.updateProgress(syncEngine.progress) }
```
With:
```swift
let wordProgresses = syncEngine.wordProgresses
forEachOverlay { $0.updateWordProgresses(wordProgresses) }
forEachOverlay { $0.updateProgress(syncEngine.progress) }
```

For widget, replace:
```swift
forEachWidget { $0.updateLyrics(lines: lines, currentIndex: index) }
```
With:
```swift
forEachWidget { $0.updateLyrics(lines: lines, currentIndex: index, words: currentWords) }
```

Replace:
```swift
forEachWidget { $0.updateProgress(syncEngine.progress) }
```
With:
```swift
forEachWidget { $0.updateWordProgresses(wordProgresses) }
```

Also update the intro section where `showTrackInfo` is called — no change needed since `showTrackInfo` internally calls `updateLyrics` with default empty words.

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeded.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/AppDelegate.swift
git commit -m "feat: wire word progresses from SyncEngine to displays"
```

---

### Task 8: Run all tests + verification

**Files:** None (verification only)

- [ ] **Step 1: Run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 2: Build release**

Run: `swift build -c release 2>&1 | tail -5`
Expected: Build succeeded.

- [ ] **Step 3: Manual verification**

Launch: `swift build && .build/debug/yalyric`

1. Play a popular song (likely to have Musixmatch richsync) → words should fill individually
2. Check logs for `[musixmatch] Got richsync with N lines` to confirm richsync is being used
3. Play a less popular song (LRCLIB only) → words should fill proportionally (estimated timing)
4. Toggle karaoke fill off in Settings → words display as plain text, no gradient
5. Toggle back on → gradient masks reappear
6. Test all transition styles (slide up, crossfade, scale fade, push) → animations work on word stacks
7. Desktop widget → highlight line shows per-word fill

- [ ] **Step 4: Commit if fixes needed**

```bash
git add -A
git commit -m "fix: address issues found during word-level karaoke verification"
```
