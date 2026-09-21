import XCTest
@testable import yalyricLib

/// Pairing NetEase's `tlyric` / `romalrc` payloads onto the original `lrc` lines.
///
/// All fixture text is invented placeholder content, not real lyrics.
final class LyricAlignmentTests: XCTestCase {

    private func line(_ time: TimeInterval, _ text: String) -> LyricLine {
        LyricLine(time: time, text: text)
    }

    func testPairsTranslationOntoOriginalByTimestamp() {
        let original = [line(12.0, "original one"), line(17.2, "original two")]
        let translation = [line(12.0, "译文一"), line(17.2, "译文二")]

        let merged = LyricAlignment.merge(original: original, translation: translation, romaji: [])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].translation, "译文一")
        XCTAssertEqual(merged[1].translation, "译文二")
    }

    func testOriginalLineWithoutTranslationGetsNil() {
        // NetEase leaves credit lines at the top of a track untranslated.
        let original = [line(0.0, "credit line"), line(12.0, "original one")]
        let translation = [line(12.0, "译文一")]

        let merged = LyricAlignment.merge(original: original, translation: translation, romaji: [])

        XCTAssertNil(merged[0].translation)
        XCTAssertEqual(merged[1].translation, "译文一")
    }

    func testPairsWithinToleranceWindow() {
        // `[00:12.0]` and `[00:12.00]` land 30ms apart through LRCParser's
        // centisecond branch; they are still the same line.
        let original = [line(12.00, "original one")]
        let translation = [line(12.03, "译文一")]

        let merged = LyricAlignment.merge(original: original, translation: translation, romaji: [])

        XCTAssertEqual(merged[0].translation, "译文一")
    }

    func testDoesNotPairBeyondToleranceWindow() {
        let original = [line(12.0, "original one")]
        let translation = [line(14.0, "译文一")]

        let merged = LyricAlignment.merge(original: original, translation: translation, romaji: [])

        XCTAssertNil(merged[0].translation)
    }

    func testPicksNearestWhenTwoTranslationsAreInRange() {
        let original = [line(12.0, "original one")]
        let translation = [line(11.99, "closer"), line(12.02, "further")]

        let merged = LyricAlignment.merge(original: original, translation: translation, romaji: [])

        XCTAssertEqual(merged[0].translation, "closer")
    }

    func testDropsTranslationIdenticalToOriginal() {
        let original = [line(12.0, "original one")]
        let translation = [line(12.0, "original one")]

        let merged = LyricAlignment.merge(original: original, translation: translation, romaji: [])

        XCTAssertNil(merged[0].translation)
    }

    func testDropsEmptyTranslation() {
        let original = [line(12.0, "original one")]
        let translation = [line(12.0, "   ")]

        let merged = LyricAlignment.merge(original: original, translation: translation, romaji: [])

        XCTAssertNil(merged[0].translation)
    }

    func testPairsRomajiIndependentlyOfTranslation() {
        let original = [line(12.0, "原文一"), line(17.2, "原文二")]
        let translation = [line(12.0, "译文一")]
        let romaji = [line(17.2, "genbun ni")]

        let merged = LyricAlignment.merge(original: original, translation: translation, romaji: romaji)

        XCTAssertEqual(merged[0].translation, "译文一")
        XCTAssertNil(merged[0].romaji)
        XCTAssertNil(merged[1].translation)
        XCTAssertEqual(merged[1].romaji, "genbun ni")
    }

    func testPreservesOriginalTextTimeAndOrder() {
        let original = [line(12.0, "original one"), line(17.2, "original two")]
        let translation = [line(17.2, "译文二")]

        let merged = LyricAlignment.merge(original: original, translation: translation, romaji: [])

        XCTAssertEqual(merged.map(\.text), ["original one", "original two"])
        XCTAssertEqual(merged.map(\.time), [12.0, 17.2])
    }

    func testEmptyTranslationPayloadLeavesLinesUntouched() {
        let original = [line(12.0, "original one")]

        let merged = LyricAlignment.merge(original: original, translation: [], romaji: [])

        XCTAssertEqual(merged.count, 1)
        XCTAssertNil(merged[0].translation)
        XCTAssertNil(merged[0].romaji)
    }
}
