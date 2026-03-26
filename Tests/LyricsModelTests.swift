import XCTest
@testable import yalyricLib

final class LyricsModelTests: XCTestCase {

    private func makeSyncedLyrics(_ times: [Double]) -> Lyrics {
        let lines = times.enumerated().map { i, t in LyricLine(time: t, text: "Line \(i)") }
        return Lyrics(lines: lines, source: .lrclib, isSynced: true)
    }

    func testCurrentLineIndexBasic() {
        let lyrics = makeSyncedLyrics([10, 20, 30, 40, 50])
        XCTAssertEqual(lyrics.currentLineIndex(at: 10), 0)
        XCTAssertEqual(lyrics.currentLineIndex(at: 15), 0)
        XCTAssertEqual(lyrics.currentLineIndex(at: 20), 1)
        XCTAssertEqual(lyrics.currentLineIndex(at: 35), 2)
        XCTAssertEqual(lyrics.currentLineIndex(at: 50), 4)
        XCTAssertEqual(lyrics.currentLineIndex(at: 99), 4)
    }

    func testBeforeFirstLine() {
        let lyrics = makeSyncedLyrics([10, 20, 30])
        XCTAssertNil(lyrics.currentLineIndex(at: 0))
        XCTAssertNil(lyrics.currentLineIndex(at: 5))
        XCTAssertNil(lyrics.currentLineIndex(at: 9.999))
    }

    func testExactTimestamps() {
        let lyrics = makeSyncedLyrics([10, 20, 30])
        XCTAssertEqual(lyrics.currentLineIndex(at: 10), 0)
        XCTAssertEqual(lyrics.currentLineIndex(at: 20), 1)
        XCTAssertEqual(lyrics.currentLineIndex(at: 30), 2)
    }

    func testSingleLine() {
        let lyrics = makeSyncedLyrics([5.0])
        XCTAssertNil(lyrics.currentLineIndex(at: 0))
        XCTAssertEqual(lyrics.currentLineIndex(at: 5), 0)
        XCTAssertEqual(lyrics.currentLineIndex(at: 100), 0)
    }

    func testEmptyLyrics() {
        let lyrics = Lyrics(lines: [], source: .lrclib, isSynced: true)
        XCTAssertNil(lyrics.currentLineIndex(at: 0))
        XCTAssertNil(lyrics.currentLineIndex(at: 50))
    }

    func testUnsyncedReturnsNil() {
        let lines = [LyricLine(time: 0, text: "A"), LyricLine(time: 1, text: "B")]
        let lyrics = Lyrics(lines: lines, source: .plain, isSynced: false)
        XCTAssertNil(lyrics.currentLineIndex(at: 0))
        XCTAssertNil(lyrics.currentLineIndex(at: 1))
    }

    func testCloseTimestamps() {
        let lyrics = makeSyncedLyrics([10.0, 10.1, 10.2, 10.3])
        XCTAssertEqual(lyrics.currentLineIndex(at: 10.0), 0)
        XCTAssertEqual(lyrics.currentLineIndex(at: 10.05), 0)
        XCTAssertEqual(lyrics.currentLineIndex(at: 10.1), 1)
        XCTAssertEqual(lyrics.currentLineIndex(at: 10.15), 1)
        XCTAssertEqual(lyrics.currentLineIndex(at: 10.3), 3)
    }

    func testManyLines() {
        let times = (0..<1000).map { Double($0) * 2.5 }
        let lyrics = makeSyncedLyrics(times)
        XCTAssertEqual(lyrics.currentLineIndex(at: 0), 0)
        XCTAssertEqual(lyrics.currentLineIndex(at: 250), 100)
        XCTAssertEqual(lyrics.currentLineIndex(at: 1000), 400)
        XCTAssertEqual(lyrics.currentLineIndex(at: 2497.5), 999)
        XCTAssertEqual(lyrics.currentLineIndex(at: 5000), 999)
    }

    // MARK: - Scoring Tests

    private func makeLines(_ count: Int) -> [LyricLine] {
        (0..<count).map { LyricLine(time: Double($0) * 3, text: "Line \($0)") }
    }

    @MainActor
    func testScoreSyncedLangMatchManyLines() {
        // Synced(3) + lang "any" always matches(1) + >5 lines(1) = 5
        let lyrics = Lyrics(lines: makeLines(10), source: .lrclib, isSynced: true)
        let score = LyricsManager.scoreLyrics(lyrics, langPref: .any, trackName: "Test", trackArtist: "Artist")
        XCTAssertEqual(score, 5)
    }

    @MainActor
    func testScoreUnsyncedFewLines() {
        // Not synced(0) + lang "any" matches(1) + <=5 lines(0) = 1
        let lyrics = Lyrics(lines: makeLines(3), source: .plain, isSynced: false)
        let score = LyricsManager.scoreLyrics(lyrics, langPref: .any, trackName: "Test", trackArtist: "Artist")
        XCTAssertEqual(score, 1)
    }

    @MainActor
    func testScoreSyncedFewLines() {
        // Synced(3) + lang "any"(1) + <=5 lines(0) = 4
        let lyrics = Lyrics(lines: makeLines(2), source: .spotify, isSynced: true)
        let score = LyricsManager.scoreLyrics(lyrics, langPref: .any, trackName: "Test", trackArtist: "Artist")
        XCTAssertEqual(score, 4)
    }

    @MainActor
    func testScoreUnsyncedManyLines() {
        // Not synced(0) + lang "any"(1) + >5 lines(1) = 2
        let lyrics = Lyrics(lines: makeLines(20), source: .plain, isSynced: false)
        let score = LyricsManager.scoreLyrics(lyrics, langPref: .any, trackName: "Test", trackArtist: "Artist")
        XCTAssertEqual(score, 2)
    }
}
