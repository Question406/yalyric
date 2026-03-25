import Testing
@testable import yalyricLib

@Suite("LRC Parser")
struct LRCParserTests {

    // MARK: - Basic LRC Parsing

    @Test("Parse simple LRC lines")
    func parseSimpleLRC() {
        let lrc = """
        [00:12.00]Line one
        [00:17.20]Line two
        [00:21.10]Line three
        """
        let lines = LRCParser.parse(lrc)

        #expect(lines.count == 3)
        #expect(lines[0].text == "Line one")
        #expect(abs(lines[0].time - 12.0) < 0.01)
        #expect(lines[1].text == "Line two")
        #expect(abs(lines[1].time - 17.2) < 0.01)
        #expect(lines[2].text == "Line three")
        #expect(abs(lines[2].time - 21.1) < 0.01)
    }

    @Test("Parse millisecond precision [MM:SS.xxx]")
    func parseMillisecondPrecision() {
        let lrc = "[01:23.456]High precision"
        let lines = LRCParser.parse(lrc)

        #expect(lines.count == 1)
        #expect(abs(lines[0].time - 83.456) < 0.001)
        #expect(lines[0].text == "High precision")
    }

    @Test("Parse centisecond precision [MM:SS.xx]")
    func parseCentisecondPrecision() {
        let lrc = "[01:05.20]Centiseconds"
        let lines = LRCParser.parse(lrc)

        #expect(lines.count == 1)
        #expect(abs(lines[0].time - 65.2) < 0.01)
    }

    @Test("Parse without subseconds [MM:SS]")
    func parseNoSubseconds() {
        let lrc = "[02:30]No decimal"
        let lines = LRCParser.parse(lrc)

        #expect(lines.count == 1)
        #expect(abs(lines[0].time - 150.0) < 0.01)
    }

    @Test("Parse multiple time tags on same line")
    func parseMultipleTimeTags() {
        let lrc = "[00:10.00][00:50.00][01:30.00]Repeated chorus"
        let lines = LRCParser.parse(lrc)

        #expect(lines.count == 3)
        for line in lines {
            #expect(line.text == "Repeated chorus")
        }
        #expect(abs(lines[0].time - 10.0) < 0.01)
        #expect(abs(lines[1].time - 50.0) < 0.01)
        #expect(abs(lines[2].time - 90.0) < 0.01)
    }

    @Test("Output is sorted by time")
    func parseSortsByTime() {
        let lrc = """
        [00:30.00]Second
        [00:10.00]First
        [00:50.00]Third
        """
        let lines = LRCParser.parse(lrc)

        #expect(lines[0].text == "First")
        #expect(lines[1].text == "Second")
        #expect(lines[2].text == "Third")
    }

    @Test("Empty string returns no lines")
    func parseEmptyString() {
        #expect(LRCParser.parse("").isEmpty)
    }

    @Test("Lines without time tags are skipped")
    func parseNoTimeTags() {
        let lrc = """
        Just some text
        Without any time tags
        """
        #expect(LRCParser.parse(lrc).isEmpty)
    }

    @Test("Blank lines are skipped")
    func parseSkipsBlankLines() {
        let lrc = """
        [00:10.00]Line one

        [00:20.00]Line two

        """
        #expect(LRCParser.parse(lrc).count == 2)
    }

    @Test("Metadata tags like [ti:...] are ignored")
    func parseMetadataTags() {
        let lrc = """
        [ti:Song Title]
        [ar:Artist Name]
        [00:10.00]Actual lyric
        """
        let lines = LRCParser.parse(lrc)
        #expect(lines.count == 1)
        #expect(lines[0].text == "Actual lyric")
    }

    @Test("Large minute values (e.g. 120 minutes)")
    func parseLargeMinutes() {
        let lrc = "[120:00.00]Two hours in"
        let lines = LRCParser.parse(lrc)

        #expect(lines.count == 1)
        #expect(abs(lines[0].time - 7200.0) < 0.01)
    }

    @Test("Empty lyric text after time tag")
    func parseEmptyLyricText() {
        let lrc = "[00:15.00]"
        let lines = LRCParser.parse(lrc)

        #expect(lines.count == 1)
        #expect(lines[0].text == "")
    }

    @Test("Unicode text (CJK, accented, emoji)")
    func parseUnicodeText() {
        let lrc = """
        [00:05.00]你好世界
        [00:10.00]こんにちは
        [00:15.00]Ça va bien 🎵
        """
        let lines = LRCParser.parse(lrc)

        #expect(lines.count == 3)
        #expect(lines[0].text == "你好世界")
        #expect(lines[1].text == "こんにちは")
        #expect(lines[2].text == "Ça va bien 🎵")
    }

    // MARK: - Plain Lyrics Parsing

    @Test("Parse plain lyrics with sequential timestamps")
    func parsePlain() {
        let text = """
        First line
        Second line
        Third line
        """
        let lines = LRCParser.parsePlain(text)

        #expect(lines.count == 3)
        #expect(lines[0].text == "First line")
        #expect(lines[0].time == 0.0)
        #expect(lines[1].text == "Second line")
        #expect(lines[1].time == 1.0)
        #expect(lines[2].text == "Third line")
        #expect(lines[2].time == 2.0)
    }

    @Test("Plain lyrics skips blank lines")
    func parsePlainSkipsBlankLines() {
        let text = """
        Line one

        Line two

        Line three
        """
        let lines = LRCParser.parsePlain(text)
        #expect(lines.count == 3)
    }

    @Test("Plain lyrics empty string")
    func parsePlainEmpty() {
        #expect(LRCParser.parsePlain("").isEmpty)
    }

    @Test("Plain lyrics trims whitespace")
    func parsePlainTrimsWhitespace() {
        let text = "  padded line  \n  another  "
        let lines = LRCParser.parsePlain(text)

        #expect(lines.count == 2)
        #expect(lines[0].text == "padded line")
        #expect(lines[1].text == "another")
    }
}
