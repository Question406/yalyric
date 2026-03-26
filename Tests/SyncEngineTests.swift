import XCTest
@testable import yalyricLib

@MainActor
final class SyncEngineTests: XCTestCase {

    private func makeSyncedLyrics() -> Lyrics {
        Lyrics(lines: [
            LyricLine(time: 5.0, text: "First line"),
            LyricLine(time: 10.0, text: "Second line"),
            LyricLine(time: 15.0, text: "Third line"),
            LyricLine(time: 20.0, text: "Fourth line"),
        ], source: .lrclib, isSynced: true)
    }

    func testSetLyricsResetsState() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 12.0)
        XCTAssertEqual(engine.currentLineIndex, 1)
        engine.setLyrics(makeSyncedLyrics())
        XCTAssertEqual(engine.currentLineIndex, -1)
        XCTAssertEqual(engine.currentLine, "")
        XCTAssertEqual(engine.nextLine, "")
        XCTAssertEqual(engine.progress, 0)
    }

    func testSetLyricsNil() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 12.0)
        engine.setLyrics(nil)
        XCTAssertEqual(engine.currentLineIndex, -1)
        XCTAssertEqual(engine.currentLine, "")
        XCTAssertTrue(engine.allLines.isEmpty)
    }

    func testUpdateBeforeFirstLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 2.0)
        XCTAssertEqual(engine.currentLineIndex, -1)
        XCTAssertEqual(engine.currentLine, "")
        XCTAssertEqual(engine.nextLine, "First line")
    }

    func testUpdateAtFirstLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 5.0)
        XCTAssertEqual(engine.currentLineIndex, 0)
        XCTAssertEqual(engine.currentLine, "First line")
        XCTAssertEqual(engine.nextLine, "Second line")
    }

    func testUpdateMidSong() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 12.0)
        XCTAssertEqual(engine.currentLineIndex, 1)
        XCTAssertEqual(engine.currentLine, "Second line")
        XCTAssertEqual(engine.nextLine, "Third line")
    }

    func testUpdateAtLastLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 20.0)
        XCTAssertEqual(engine.currentLineIndex, 3)
        XCTAssertEqual(engine.currentLine, "Fourth line")
        XCTAssertEqual(engine.nextLine, "")
    }

    func testUpdatePastEnd() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 999.0)
        XCTAssertEqual(engine.currentLineIndex, 3)
        XCTAssertEqual(engine.currentLine, "Fourth line")
    }

    func testUpdateProgress() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 12.5)
        XCTAssertEqual(engine.currentLineIndex, 1)
        XCTAssertEqual(engine.progress, 0.5, accuracy: 0.01)
        engine.update(position: 10.0)
        XCTAssertEqual(engine.progress, 0.0, accuracy: 0.01)
        engine.update(position: 14.9)
        XCTAssertEqual(engine.progress, 0.98, accuracy: 0.01)
    }

    func testUpdateProgressLastLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 22.5)
        XCTAssertEqual(engine.currentLineIndex, 3)
        XCTAssertEqual(engine.progress, 0.5, accuracy: 0.01)
    }

    func testUpdateProgressClamped() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 100.0)
        XCTAssertEqual(engine.progress, 1.0, accuracy: 0.01)
    }

    func testUpdateUnsyncedLyrics() {
        let engine = SyncEngine()
        let lyrics = Lyrics(lines: [
            LyricLine(time: 0, text: "First"),
            LyricLine(time: 1, text: "Second"),
            LyricLine(time: 2, text: "Third"),
        ], source: .plain, isSynced: false)
        engine.setLyrics(lyrics)
        engine.update(position: 50.0)
        XCTAssertEqual(engine.currentLineIndex, 0)
        XCTAssertEqual(engine.currentLine, "First")
        XCTAssertEqual(engine.nextLine, "Second")
    }

    func testUpdateWithNoLyrics() {
        let engine = SyncEngine()
        engine.update(position: 10.0)
        XCTAssertEqual(engine.currentLineIndex, -1)
        XCTAssertEqual(engine.currentLine, "")
        XCTAssertEqual(engine.nextLine, "")
        XCTAssertEqual(engine.progress, 0)
    }

    func testUpdateWithEmptyLyrics() {
        let engine = SyncEngine()
        engine.setLyrics(Lyrics(lines: [], source: .lrclib, isSynced: true))
        engine.update(position: 10.0)
        XCTAssertEqual(engine.currentLineIndex, -1)
        XCTAssertEqual(engine.currentLine, "")
    }

    func testAllLines() {
        let engine = SyncEngine()
        XCTAssertTrue(engine.allLines.isEmpty)
        engine.setLyrics(makeSyncedLyrics())
        XCTAssertEqual(engine.allLines.count, 4)
    }

    func testIsSynced() {
        let engine = SyncEngine()
        XCTAssertFalse(engine.isSynced)
        engine.setLyrics(makeSyncedLyrics())
        XCTAssertTrue(engine.isSynced)
        engine.setLyrics(Lyrics(lines: [LyricLine(time: 0, text: "A")], source: .plain, isSynced: false))
        XCTAssertFalse(engine.isSynced)
    }

    func testSeekBackwards() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 17.0)
        XCTAssertEqual(engine.currentLineIndex, 2)
        engine.update(position: 6.0)
        XCTAssertEqual(engine.currentLineIndex, 0)
        XCTAssertEqual(engine.currentLine, "First line")
    }

    func testSeekBeforeFirstLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 12.0)
        XCTAssertEqual(engine.currentLineIndex, 1)
        engine.update(position: 1.0)
        XCTAssertEqual(engine.currentLineIndex, -1)
        XCTAssertEqual(engine.currentLine, "")
        XCTAssertEqual(engine.nextLine, "First line")
    }

    // MARK: - Offset Tests

    func testPositiveOffset() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.offset = 5.0  // lyrics 5s earlier
        // At position 5.0, adjusted = 10.0, should be on "Second line"
        engine.update(position: 5.0)
        XCTAssertEqual(engine.currentLineIndex, 1)
        XCTAssertEqual(engine.currentLine, "Second line")
    }

    func testNegativeOffset() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.offset = -3.0  // lyrics 3s later
        // At position 12.0, adjusted = 9.0, should still be on "First line"
        engine.update(position: 12.0)
        XCTAssertEqual(engine.currentLineIndex, 0)
        XCTAssertEqual(engine.currentLine, "First line")
    }

    func testOffsetProgressCalculation() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.offset = 2.0
        // At position 5.5, adjusted = 7.5, line 0 (5.0-10.0), progress = 2.5/5.0 = 0.5
        engine.update(position: 5.5)
        XCTAssertEqual(engine.currentLineIndex, 0)
        XCTAssertEqual(engine.progress, 0.5, accuracy: 0.01)
    }

    func testOffsetResetOnNewLyrics() {
        let engine = SyncEngine()
        engine.offset = 3.0
        engine.setLyrics(makeSyncedLyrics())
        // Offset should persist across setLyrics
        XCTAssertEqual(engine.offset, 3.0)
    }
}
