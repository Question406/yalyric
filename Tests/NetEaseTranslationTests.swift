import XCTest
@testable import yalyricLib

/// Decoding NetEase's three parallel lyric payloads into one set of lines.
/// All fixture text is invented placeholder content, not real lyrics.
final class NetEaseTranslationTests: XCTestCase {

    private func payload(lrc: String?, tlyric: String? = nil, romalrc: String? = nil) -> [String: Any] {
        var json: [String: Any] = [:]
        if let lrc { json["lrc"] = ["lyric": lrc] }
        if let tlyric { json["tlyric"] = ["lyric": tlyric] }
        if let romalrc { json["romalrc"] = ["lyric": romalrc] }
        return json
    }

    func testAttachesTranslationAndRomajiToMatchingLines() throws {
        let json = payload(
            lrc: "[00:12.00]original one\n[00:17.20]original two",
            tlyric: "[00:12.00]译文一\n[00:17.20]译文二",
            romalrc: "[00:12.00]gembun ichi\n[00:17.20]gembun ni"
        )

        let lyrics = try XCTUnwrap(NetEaseProvider.lyrics(from: json))

        XCTAssertEqual(lyrics.source, .netease)
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.count, 2)
        XCTAssertEqual(lyrics.lines[0].text, "original one")
        XCTAssertEqual(lyrics.lines[0].translation, "译文一")
        XCTAssertEqual(lyrics.lines[0].romaji, "gembun ichi")
        XCTAssertTrue(lyrics.hasTranslation)
        XCTAssertTrue(lyrics.hasRomaji)
    }

    /// The credit lines NetEase stacks at the top of a track are not translated.
    func testLeavesUnmatchedLinesWithoutATranslation() throws {
        let json = payload(
            lrc: "[00:00.00]credit line\n[00:12.00]original one",
            tlyric: "[00:12.00]译文一"
        )

        let lyrics = try XCTUnwrap(NetEaseProvider.lyrics(from: json))

        XCTAssertNil(lyrics.lines[0].translation)
        XCTAssertEqual(lyrics.lines[1].translation, "译文一")
    }

    func testTreatsAnEmptyTranslationPayloadAsAbsent() throws {
        let json = payload(lrc: "[00:12.00]original one", tlyric: "")

        let lyrics = try XCTUnwrap(NetEaseProvider.lyrics(from: json))

        XCTAssertEqual(lyrics.lines.count, 1)
        XCTAssertFalse(lyrics.hasTranslation)
    }

    func testStillWorksWhenOnlyTheOriginalIsPresent() throws {
        let json = payload(lrc: "[00:12.00]original one\n[00:17.20]original two")

        let lyrics = try XCTUnwrap(NetEaseProvider.lyrics(from: json))

        XCTAssertEqual(lyrics.lines.count, 2)
        XCTAssertFalse(lyrics.hasTranslation)
        XCTAssertFalse(lyrics.hasRomaji)
    }

    func testReturnsNilWhenThereIsNoOriginal() {
        XCTAssertNil(NetEaseProvider.lyrics(from: payload(lrc: nil, tlyric: "[00:12.00]译文一")))
        XCTAssertNil(NetEaseProvider.lyrics(from: payload(lrc: "")))
    }

    /// A translation that is just the source text repeated is not worth a line.
    func testIgnoresATranslationIdenticalToTheOriginal() throws {
        let json = payload(lrc: "[00:12.00]original one", tlyric: "[00:12.00]original one")

        let lyrics = try XCTUnwrap(NetEaseProvider.lyrics(from: json))

        XCTAssertFalse(lyrics.hasTranslation)
    }
}
