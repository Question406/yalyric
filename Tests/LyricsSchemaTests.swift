import XCTest
@testable import yalyricLib

/// The disk cache format, and the helpers scoring uses to spot a translated result.
final class LyricsSchemaTests: XCTestCase {

    /// Entries written before bilingual support have no translation fields and
    /// would otherwise be served from disk forever, so turning the setting on
    /// would appear to do nothing on exactly the tracks played most.
    /// `schemaVersion` is non-optional so those entries fail to decode and
    /// refetch once. Making it optional would silently reintroduce the bug.
    func testCacheEntryWithoutSchemaVersionFailsToDecode() throws {
        let legacy = #"{"lines":[{"time":12,"text":"original one"}],"source":"netease","isSynced":true}"#
        let data = try XCTUnwrap(legacy.data(using: .utf8))

        XCTAssertThrowsError(try JSONDecoder().decode(Lyrics.self, from: data))
    }

    func testCurrentCacheEntryRoundTrips() throws {
        let lyrics = Lyrics(
            lines: [LyricLine(time: 12, text: "original one", translation: "译文一", romaji: "genbun")],
            source: .netease,
            isSynced: true
        )

        let data = try JSONEncoder().encode(lyrics)
        let decoded = try JSONDecoder().decode(Lyrics.self, from: data)

        XCTAssertEqual(decoded.lines.count, 1)
        XCTAssertEqual(decoded.lines[0].translation, "译文一")
        XCTAssertEqual(decoded.lines[0].romaji, "genbun")
        XCTAssertEqual(decoded.schemaVersion, Lyrics.currentSchemaVersion)
    }

    func testHasTranslationIsTrueWhenAnyLineCarriesOne() {
        let lyrics = Lyrics(
            lines: [
                LyricLine(time: 0, text: "credit line"),
                LyricLine(time: 12, text: "original one", translation: "译文一")
            ],
            source: .netease, isSynced: true
        )

        XCTAssertTrue(lyrics.hasTranslation)
        XCTAssertFalse(lyrics.hasRomaji)
    }

    func testHasTranslationIsFalseForAnUntranslatedResult() {
        let lyrics = Lyrics(
            lines: [LyricLine(time: 12, text: "original one")],
            source: .lrclib, isSynced: true
        )

        XCTAssertFalse(lyrics.hasTranslation)
    }

    func testHasRomajiIsTrueWhenAnyLineCarriesOne() {
        let lyrics = Lyrics(
            lines: [LyricLine(time: 12, text: "原文一", romaji: "genbun ichi")],
            source: .netease, isSynced: true
        )

        XCTAssertTrue(lyrics.hasRomaji)
        XCTAssertFalse(lyrics.hasTranslation)
    }
}
