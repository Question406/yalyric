import XCTest
@testable import yalyricLib

/// Regression tests for the "Spotify shows lyrics but yalyric doesn't" class of bugs.
/// Every case here is taken from a real failure captured in ~/Library/Logs/yalyric.log.
final class LyricsMatchingTests: XCTestCase {

    private func track(_ name: String, _ artist: String, _ duration: TimeInterval) -> TrackInfo {
        TrackInfo(id: "spotify:track:test", name: name, artist: artist, album: "", duration: duration)
    }

    // MARK: - TitleNormalizer

    func testStripsCJKQualifierSuffix() {
        XCTAssertEqual(TitleNormalizer.normalize("甲乙丙丁Strangers - 粵語版"), "甲乙丙丁Strangers")
    }

    func testStripsRemasteredSuffix() {
        XCTAssertEqual(TitleNormalizer.normalize("Bohemian Rhapsody - Remastered 2011"), "Bohemian Rhapsody")
    }

    func testStripsLiveSuffix() {
        XCTAssertEqual(TitleNormalizer.normalize("Wish You Were Here - Live"), "Wish You Were Here")
    }

    func testStripsFeatParenthetical() {
        XCTAssertEqual(TitleNormalizer.normalize("Stay (feat. Justin Bieber)"), "Stay")
    }

    func testStripsCJKParentheticalQualifier() {
        XCTAssertEqual(TitleNormalizer.normalize("甲乙丙丁 (粤语版)"), "甲乙丙丁")
    }

    func testKeepsPlainTitleUnchanged() {
        XCTAssertEqual(TitleNormalizer.normalize("執迷不悔"), "執迷不悔")
    }

    func testDoesNotStripHyphenatedWords() {
        XCTAssertEqual(TitleNormalizer.normalize("Jack-in-the-box"), "Jack-in-the-box")
    }

    func testDoesNotStripMeaningfulDashSuffix() {
        // " - A Little" is part of the title, not a qualifier — must survive.
        XCTAssertEqual(TitleNormalizer.normalize("Marry Me - A Little"), "Marry Me - A Little")
    }

    // MARK: - SearchMatchScore

    /// Spotify reports Traditional Han + a romanised artist; NetEase reports Simplified Han
    /// + the Chinese artist name. Duration matches to 40ms. This is the exact track from
    /// the log that was rejected with score 2.
    func testAcceptsTraditionalSimplifiedNameMatch() {
        let score = SearchMatchScore.score(
            provider: "netease",
            resultName: "执迷不悔",
            resultArtist: "王菲",
            resultDurationMs: 273_840,
            track: track("執迷不悔", "Faye Wong", 273.8)
        )
        XCTAssertGreaterThanOrEqual(score, SearchMatchScore.minimumScore)
    }

    /// The decorated Spotify title must still match NetEase's parenthetical-qualified name.
    func testAcceptsQualifierDecoratedNamesOnBothSides() {
        let score = SearchMatchScore.score(
            provider: "netease",
            resultName: "甲乙丙丁 (粤语版)",
            resultArtist: "李佳薇",
            resultDurationMs: 209_538,
            track: track("甲乙丙丁Strangers - 粵語版", "Jess Lee", 209.5)
        )
        XCTAssertGreaterThanOrEqual(score, SearchMatchScore.minimumScore)
    }

    /// Guard against loosening the threshold: 演员 is a completely different song that
    /// happens to fall inside the 30s duration tolerance. It must stay rejected.
    func testRejectsUnrelatedSongWithinDurationTolerance() {
        let score = SearchMatchScore.score(
            provider: "netease",
            resultName: "演员",
            resultArtist: "薛之谦",
            resultDurationMs: 261_200,
            track: track("執迷不悔", "Faye Wong", 273.8)
        )
        XCTAssertLessThan(score, SearchMatchScore.minimumScore)
    }

    /// A fused bilingual title ("甲乙丙丁Strangers") must not match an unrelated English
    /// song called "Strangers" just because the track name happens to contain that word.
    /// This produced English lyrics for a Cantonese track.
    func testRejectsUnrelatedSongMatchingOnlyAFusedTitleFragment() {
        let score = SearchMatchScore.score(
            provider: "netease",
            resultName: "Strangers",
            resultArtist: "Ethel Cain",
            resultDurationMs: 209_000,
            track: track("甲乙丙丁Strangers - 粵語版", "Jess Lee", 209.5)
        )
        XCTAssertLessThan(score, SearchMatchScore.minimumScore)
    }

    func testRejectsCompletelyUnrelatedResult() {
        let score = SearchMatchScore.score(
            provider: "musixmatch",
            resultName: "NOKIA",
            resultArtist: "Drake",
            resultDurationMs: nil,
            track: track("執迷不悔", "Faye Wong", 273.8)
        )
        XCTAssertLessThan(score, SearchMatchScore.minimumScore)
    }

    func testPlainAsciiMatchStillScores() {
        let score = SearchMatchScore.score(
            provider: "lrclib",
            resultName: "Bohemian Rhapsody",
            resultArtist: "Queen",
            resultDurationMs: 355_000,
            track: track("Bohemian Rhapsody - Remastered 2011", "Queen", 355.0)
        )
        XCTAssertGreaterThanOrEqual(score, SearchMatchScore.minimumScore)
    }

    // MARK: - Rejection log attribution

    func testRejectionMessageIdentifiesProvider() {
        let message = SearchMatchScore.rejectionMessage(
            provider: "netease",
            resultName: "演员",
            resultArtist: "薛之谦",
            durationDiff: 12.6,
            nameMatch: false,
            artistMatch: false,
            score: 2
        )
        XCTAssertTrue(message.contains("[netease]"), "rejection log must name the provider, got: \(message)")
        XCTAssertTrue(message.contains("演员"))
    }
}
