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
