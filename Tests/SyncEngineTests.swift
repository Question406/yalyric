import Testing
@testable import LyricSyncLib

@Suite("SyncEngine")
@MainActor
struct SyncEngineTests {

    private func makeSyncedLyrics() -> Lyrics {
        let lines = [
            LyricLine(time: 5.0, text: "First line"),
            LyricLine(time: 10.0, text: "Second line"),
            LyricLine(time: 15.0, text: "Third line"),
            LyricLine(time: 20.0, text: "Fourth line"),
        ]
        return Lyrics(lines: lines, source: .lrclib, isSynced: true)
    }

    // MARK: - setLyrics

    @Test("setLyrics resets all state")
    func setLyricsResetsState() {
        let engine = SyncEngine()
        let lyrics = makeSyncedLyrics()

        engine.setLyrics(lyrics)
        engine.update(position: 12.0)
        #expect(engine.currentLineIndex == 1)

        engine.setLyrics(lyrics)
        #expect(engine.currentLineIndex == -1)
        #expect(engine.currentLine == "")
        #expect(engine.nextLine == "")
        #expect(engine.progress == 0)
    }

    @Test("setLyrics(nil) clears everything")
    func setLyricsNil() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())
        engine.update(position: 12.0)

        engine.setLyrics(nil)
        #expect(engine.currentLineIndex == -1)
        #expect(engine.currentLine == "")
        #expect(engine.allLines.isEmpty)
    }

    // MARK: - update(position:) with synced lyrics

    @Test("Before first lyric line")
    func updateBeforeFirstLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())

        engine.update(position: 2.0)
        #expect(engine.currentLineIndex == -1)
        #expect(engine.currentLine == "")
        #expect(engine.nextLine == "First line")
    }

    @Test("At first lyric line")
    func updateAtFirstLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())

        engine.update(position: 5.0)
        #expect(engine.currentLineIndex == 0)
        #expect(engine.currentLine == "First line")
        #expect(engine.nextLine == "Second line")
    }

    @Test("Mid-song position")
    func updateMidSong() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())

        engine.update(position: 12.0)
        #expect(engine.currentLineIndex == 1)
        #expect(engine.currentLine == "Second line")
        #expect(engine.nextLine == "Third line")
    }

    @Test("At last lyric line")
    func updateAtLastLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())

        engine.update(position: 20.0)
        #expect(engine.currentLineIndex == 3)
        #expect(engine.currentLine == "Fourth line")
        #expect(engine.nextLine == "")
    }

    @Test("Past end of lyrics")
    func updatePastEnd() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())

        engine.update(position: 999.0)
        #expect(engine.currentLineIndex == 3)
        #expect(engine.currentLine == "Fourth line")
    }

    @Test("Progress within a line")
    func updateProgress() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())

        // Between 10.0 and 15.0 (5s duration)
        engine.update(position: 12.5)
        #expect(engine.currentLineIndex == 1)
        #expect(abs(engine.progress - 0.5) < 0.01)

        engine.update(position: 10.0)
        #expect(abs(engine.progress - 0.0) < 0.01)

        engine.update(position: 14.9)
        #expect(abs(engine.progress - 0.98) < 0.01)
    }

    @Test("Progress on last line (assumes 5s duration)")
    func updateProgressLastLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())

        engine.update(position: 22.5)
        #expect(engine.currentLineIndex == 3)
        #expect(abs(engine.progress - 0.5) < 0.01)
    }

    @Test("Progress clamped to 1.0")
    func updateProgressClamped() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())

        engine.update(position: 100.0)
        #expect(abs(engine.progress - 1.0) < 0.01)
    }

    // MARK: - Unsynced lyrics

    @Test("Unsynced lyrics shows first line")
    func updateUnsyncedLyrics() {
        let engine = SyncEngine()
        let lines = [
            LyricLine(time: 0, text: "First"),
            LyricLine(time: 1, text: "Second"),
            LyricLine(time: 2, text: "Third"),
        ]
        let lyrics = Lyrics(lines: lines, source: .plain, isSynced: false)
        engine.setLyrics(lyrics)

        engine.update(position: 50.0)
        #expect(engine.currentLineIndex == 0)
        #expect(engine.currentLine == "First")
        #expect(engine.nextLine == "Second")
    }

    // MARK: - No lyrics

    @Test("No lyrics set")
    func updateWithNoLyrics() {
        let engine = SyncEngine()
        engine.update(position: 10.0)

        #expect(engine.currentLineIndex == -1)
        #expect(engine.currentLine == "")
        #expect(engine.nextLine == "")
        #expect(engine.progress == 0)
    }

    @Test("Empty synced lyrics")
    func updateWithEmptyLyrics() {
        let engine = SyncEngine()
        engine.setLyrics(Lyrics(lines: [], source: .lrclib, isSynced: true))

        engine.update(position: 10.0)
        #expect(engine.currentLineIndex == -1)
        #expect(engine.currentLine == "")
    }

    // MARK: - allLines / isSynced

    @Test("allLines reflects current lyrics")
    func allLines() {
        let engine = SyncEngine()
        #expect(engine.allLines.isEmpty)

        engine.setLyrics(makeSyncedLyrics())
        #expect(engine.allLines.count == 4)
    }

    @Test("isSynced reflects lyrics state")
    func isSynced() {
        let engine = SyncEngine()
        #expect(engine.isSynced == false)

        engine.setLyrics(makeSyncedLyrics())
        #expect(engine.isSynced == true)

        let unsynced = Lyrics(lines: [LyricLine(time: 0, text: "A")], source: .plain, isSynced: false)
        engine.setLyrics(unsynced)
        #expect(engine.isSynced == false)
    }

    // MARK: - Seeking

    @Test("Seek backwards updates correctly")
    func seekBackwards() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())

        engine.update(position: 17.0)
        #expect(engine.currentLineIndex == 2)
        #expect(engine.currentLine == "Third line")

        engine.update(position: 6.0)
        #expect(engine.currentLineIndex == 0)
        #expect(engine.currentLine == "First line")
    }

    @Test("Seek before first line after playing")
    func seekBeforeFirstLine() {
        let engine = SyncEngine()
        engine.setLyrics(makeSyncedLyrics())

        engine.update(position: 12.0)
        #expect(engine.currentLineIndex == 1)

        engine.update(position: 1.0)
        #expect(engine.currentLineIndex == -1)
        #expect(engine.currentLine == "")
        #expect(engine.nextLine == "First line")
    }
}
