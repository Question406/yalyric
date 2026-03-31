import XCTest
@testable import yalyricLib

final class WordTimingTests: XCTestCase {

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

    func testEstimateWordTimings() {
        let words = SyncEngine.estimateWordTimings(text: "I love you", lineDuration: 3.0)
        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(words[0].text, "I")
        XCTAssertEqual(words[0].offset, 0.0, accuracy: 0.01)
        XCTAssertEqual(words[1].text, "love")
        XCTAssertEqual(words[1].offset, 0.375, accuracy: 0.01)
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
        engine.update(position: 1.5)
        XCTAssertEqual(engine.wordProgresses.count, 3)
        XCTAssertEqual(engine.wordProgresses[0], 1.0, accuracy: 0.01)
        XCTAssertEqual(engine.wordProgresses[1], 0.5, accuracy: 0.01)
        XCTAssertEqual(engine.wordProgresses[2], 0.0, accuracy: 0.01)
    }

    func testWordProgressesEndOfLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeLyricsWithWords())
        engine.update(position: 4.9)
        XCTAssertEqual(engine.wordProgresses[0], 1.0, accuracy: 0.01)
        XCTAssertEqual(engine.wordProgresses[1], 1.0, accuracy: 0.01)
        XCTAssertEqual(engine.wordProgresses[2], 1.0, accuracy: 0.1)
    }

    func testWordProgressesEstimated() {
        let engine = SyncEngine()
        let lyrics = Lyrics(lines: [
            LyricLine(time: 0.0, text: "AB CD"),
            LyricLine(time: 4.0, text: "Next"),
        ], source: .lrclib, isSynced: true)
        engine.setLyrics(lyrics)
        engine.update(position: 2.0)
        XCTAssertEqual(engine.wordProgresses.count, 2)
        XCTAssertEqual(engine.wordProgresses[0], 1.0, accuracy: 0.01)
        XCTAssertEqual(engine.wordProgresses[1], 0.0, accuracy: 0.01)
    }

    func testWordProgressesResetOnLineChange() {
        let engine = SyncEngine()
        engine.setLyrics(makeLyricsWithWords())
        engine.update(position: 3.0)
        XCTAssertEqual(engine.wordProgresses.count, 3)
        engine.update(position: 5.5)
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
        engine.update(position: -1.0)
        XCTAssertTrue(engine.wordProgresses.isEmpty)
        XCTAssertTrue(engine.currentWords.isEmpty)
    }
}

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
