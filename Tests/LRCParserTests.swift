import XCTest
@testable import yalyricLib

final class LRCParserTests: XCTestCase {

    func testParseSimpleLRC() {
        let lrc = """
        [00:12.00]Line one
        [00:17.20]Line two
        [00:21.10]Line three
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "Line one")
        XCTAssertEqual(lines[0].time, 12.0, accuracy: 0.01)
        XCTAssertEqual(lines[1].text, "Line two")
        XCTAssertEqual(lines[1].time, 17.2, accuracy: 0.01)
        XCTAssertEqual(lines[2].text, "Line three")
        XCTAssertEqual(lines[2].time, 21.1, accuracy: 0.01)
    }

    func testParseMillisecondPrecision() {
        let lines = LRCParser.parse("[01:23.456]High precision")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].time, 83.456, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "High precision")
    }

    func testParseCentisecondPrecision() {
        let lines = LRCParser.parse("[01:05.20]Centiseconds")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].time, 65.2, accuracy: 0.01)
    }

    func testParseNoSubseconds() {
        let lines = LRCParser.parse("[02:30]No decimal")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].time, 150.0, accuracy: 0.01)
    }

    func testParseMultipleTimeTags() {
        let lines = LRCParser.parse("[00:10.00][00:50.00][01:30.00]Repeated chorus")
        XCTAssertEqual(lines.count, 3)
        for line in lines { XCTAssertEqual(line.text, "Repeated chorus") }
        XCTAssertEqual(lines[0].time, 10.0, accuracy: 0.01)
        XCTAssertEqual(lines[1].time, 50.0, accuracy: 0.01)
        XCTAssertEqual(lines[2].time, 90.0, accuracy: 0.01)
    }

    func testParseSortsByTime() {
        let lines = LRCParser.parse("[00:30.00]Second\n[00:10.00]First\n[00:50.00]Third")
        XCTAssertEqual(lines[0].text, "First")
        XCTAssertEqual(lines[1].text, "Second")
        XCTAssertEqual(lines[2].text, "Third")
    }

    func testParseEmptyString() { XCTAssertTrue(LRCParser.parse("").isEmpty) }

    func testParseNoTimeTags() {
        XCTAssertTrue(LRCParser.parse("Just some text\nWithout any time tags").isEmpty)
    }

    func testParseSkipsBlankLines() {
        XCTAssertEqual(LRCParser.parse("[00:10.00]Line one\n\n[00:20.00]Line two\n").count, 2)
    }

    func testParseMetadataTags() {
        let lines = LRCParser.parse("[ti:Song Title]\n[ar:Artist Name]\n[00:10.00]Actual lyric")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "Actual lyric")
    }

    func testParseLargeMinutes() {
        let lines = LRCParser.parse("[120:00.00]Two hours in")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].time, 7200.0, accuracy: 0.01)
    }

    func testParseEmptyLyricText() {
        let lines = LRCParser.parse("[00:15.00]")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "")
    }

    func testParseUnicodeText() {
        let lines = LRCParser.parse("[00:05.00]你好世界\n[00:10.00]こんにちは\n[00:15.00]Ça va bien 🎵")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "你好世界")
        XCTAssertEqual(lines[1].text, "こんにちは")
        XCTAssertEqual(lines[2].text, "Ça va bien 🎵")
    }

    func testParsePlain() {
        let lines = LRCParser.parsePlain("First line\nSecond line\nThird line")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "First line")
        XCTAssertEqual(lines[0].time, 0.0)
        XCTAssertEqual(lines[1].time, 1.0)
        XCTAssertEqual(lines[2].time, 2.0)
    }

    func testParsePlainSkipsBlankLines() {
        XCTAssertEqual(LRCParser.parsePlain("Line one\n\nLine two\n\nLine three").count, 3)
    }

    func testParsePlainEmpty() { XCTAssertTrue(LRCParser.parsePlain("").isEmpty) }

    func testParsePlainTrimsWhitespace() {
        let lines = LRCParser.parsePlain("  padded line  \n  another  ")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "padded line")
        XCTAssertEqual(lines[1].text, "another")
    }
}
