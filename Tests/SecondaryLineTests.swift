import XCTest
@testable import yalyricLib

/// What the overlay's second line resolves to. All fixture text is invented.
@MainActor
final class SecondaryLineTests: XCTestCase {

    private func bilingualLyrics() -> Lyrics {
        Lyrics(lines: [
            LyricLine(time: 5.0, text: "First line", translation: "第一行", romaji: "daiichi gyou"),
            LyricLine(time: 10.0, text: "Second line", translation: "第二行", romaji: "daini gyou"),
            // NetEase leaves some lines untranslated; this one has neither.
            LyricLine(time: 15.0, text: "Third line"),
            LyricLine(time: 20.0, text: "Fourth line", translation: "第四行", romaji: "daiyon gyou"),
        ], source: .netease, isSynced: true)
    }

    func testDefaultsToNextLine() {
        let engine = SyncEngine()
        engine.setLyrics(bilingualLyrics())
        engine.update(position: 12.0)

        XCTAssertEqual(engine.secondaryContent, .nextLine)
        XCTAssertEqual(engine.secondaryLine, "Third line")
    }

    func testShowsTranslationWhenSelected() {
        let engine = SyncEngine()
        engine.secondaryContent = .translation
        engine.setLyrics(bilingualLyrics())
        engine.update(position: 12.0)

        XCTAssertEqual(engine.currentLine, "Second line")
        XCTAssertEqual(engine.secondaryLine, "第二行")
    }

    func testShowsRomajiWhenSelected() {
        let engine = SyncEngine()
        engine.secondaryContent = .romaji
        engine.setLyrics(bilingualLyrics())
        engine.update(position: 12.0)

        XCTAssertEqual(engine.secondaryLine, "daini gyou")
    }

    /// Fallback is per line, not per track: one untranslated line in the middle
    /// of a translated song shows the upcoming lyric rather than a blank gap.
    func testFallsBackToNextLineForAnUntranslatedLine() {
        let engine = SyncEngine()
        engine.secondaryContent = .translation
        engine.setLyrics(bilingualLyrics())
        engine.update(position: 17.0)

        XCTAssertEqual(engine.currentLine, "Third line")
        XCTAssertEqual(engine.secondaryLine, "Fourth line")
    }

    func testChangingModeUpdatesWithoutWaitingForTheNextLine() {
        let engine = SyncEngine()
        engine.setLyrics(bilingualLyrics())
        engine.update(position: 12.0)
        XCTAssertEqual(engine.secondaryLine, "Third line")

        engine.secondaryContent = .translation

        XCTAssertEqual(engine.secondaryLine, "第二行")
    }

    func testClearedWhenLyricsAreReplaced() {
        let engine = SyncEngine()
        engine.secondaryContent = .translation
        engine.setLyrics(bilingualLyrics())
        engine.update(position: 12.0)

        engine.setLyrics(nil)

        XCTAssertEqual(engine.secondaryLine, "")
    }

    func testUntranslatedLyricsBehaveExactlyLikeNextLineMode() {
        let plain = Lyrics(lines: [
            LyricLine(time: 5.0, text: "First line"),
            LyricLine(time: 10.0, text: "Second line"),
        ], source: .lrclib, isSynced: true)

        let engine = SyncEngine()
        engine.secondaryContent = .translation
        engine.setLyrics(plain)
        engine.update(position: 6.0)

        XCTAssertEqual(engine.secondaryLine, "Second line")
    }

    func testRawValuesArePersistableSettingStrings() {
        XCTAssertEqual(SecondaryLine.nextLine.rawValue, "Next Line")
        XCTAssertEqual(SecondaryLine(rawValue: "Chinese Translation"), .translation)
        XCTAssertEqual(SecondaryLine.allCases.count, 3)
    }
}
