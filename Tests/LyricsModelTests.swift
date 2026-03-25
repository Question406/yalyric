import Testing
@testable import LyricSyncLib

@Suite("Lyrics Model — Binary Search")
struct LyricsModelTests {

    private func makeSyncedLyrics(_ times: [Double]) -> Lyrics {
        let lines = times.enumerated().map { i, t in
            LyricLine(time: t, text: "Line \(i)")
        }
        return Lyrics(lines: lines, source: .lrclib, isSynced: true)
    }

    @Test("Basic index lookup at various positions")
    func currentLineIndexBasic() {
        let lyrics = makeSyncedLyrics([10, 20, 30, 40, 50])

        #expect(lyrics.currentLineIndex(at: 10) == 0)
        #expect(lyrics.currentLineIndex(at: 15) == 0)
        #expect(lyrics.currentLineIndex(at: 20) == 1)
        #expect(lyrics.currentLineIndex(at: 35) == 2)
        #expect(lyrics.currentLineIndex(at: 50) == 4)
        #expect(lyrics.currentLineIndex(at: 99) == 4)
    }

    @Test("Returns nil before the first line")
    func beforeFirstLine() {
        let lyrics = makeSyncedLyrics([10, 20, 30])
        #expect(lyrics.currentLineIndex(at: 0) == nil)
        #expect(lyrics.currentLineIndex(at: 5) == nil)
        #expect(lyrics.currentLineIndex(at: 9.999) == nil)
    }

    @Test("Exact timestamps match the corresponding line")
    func exactTimestamps() {
        let lyrics = makeSyncedLyrics([10, 20, 30])

        #expect(lyrics.currentLineIndex(at: 10) == 0)
        #expect(lyrics.currentLineIndex(at: 20) == 1)
        #expect(lyrics.currentLineIndex(at: 30) == 2)
    }

    @Test("Single line lyrics")
    func singleLine() {
        let lyrics = makeSyncedLyrics([5.0])

        #expect(lyrics.currentLineIndex(at: 0) == nil)
        #expect(lyrics.currentLineIndex(at: 5) == 0)
        #expect(lyrics.currentLineIndex(at: 100) == 0)
    }

    @Test("Empty lyrics returns nil")
    func emptyLyrics() {
        let lyrics = Lyrics(lines: [], source: .lrclib, isSynced: true)
        #expect(lyrics.currentLineIndex(at: 0) == nil)
        #expect(lyrics.currentLineIndex(at: 50) == nil)
    }

    @Test("Unsynced lyrics always return nil")
    func unsyncedReturnsNil() {
        let lines = [LyricLine(time: 0, text: "A"), LyricLine(time: 1, text: "B")]
        let lyrics = Lyrics(lines: lines, source: .plain, isSynced: false)

        #expect(lyrics.currentLineIndex(at: 0) == nil)
        #expect(lyrics.currentLineIndex(at: 1) == nil)
    }

    @Test("Close timestamps (100ms apart)")
    func closeTimestamps() {
        let lyrics = makeSyncedLyrics([10.0, 10.1, 10.2, 10.3])

        #expect(lyrics.currentLineIndex(at: 10.0) == 0)
        #expect(lyrics.currentLineIndex(at: 10.05) == 0)
        #expect(lyrics.currentLineIndex(at: 10.1) == 1)
        #expect(lyrics.currentLineIndex(at: 10.15) == 1)
        #expect(lyrics.currentLineIndex(at: 10.3) == 3)
    }

    @Test("1000 lines — binary search correctness")
    func manyLines() {
        let times = (0..<1000).map { Double($0) * 2.5 }
        let lyrics = makeSyncedLyrics(times)

        #expect(lyrics.currentLineIndex(at: 0) == 0)
        #expect(lyrics.currentLineIndex(at: 250) == 100)
        #expect(lyrics.currentLineIndex(at: 1000) == 400)
        #expect(lyrics.currentLineIndex(at: 2497.5) == 999)
        #expect(lyrics.currentLineIndex(at: 5000) == 999)
    }
}
