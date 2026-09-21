import XCTest
@testable import yalyricLib

/// Provider selection once a translation is worth points. Fixture text invented.
@MainActor
final class LyricsTranslationScoringTests: XCTestCase {

    /// Synced, long enough, language-agnostic: the shape of a good LRCLIB hit,
    /// which is what NetEase has to beat.
    private func untranslated(source: LyricsSource = .lrclib) -> Lyrics {
        Lyrics(lines: (0..<8).map { LyricLine(time: Double($0) * 5, text: "line \($0)") },
               source: source, isSynced: true)
    }

    private func translated() -> Lyrics {
        Lyrics(lines: (0..<8).map {
            LyricLine(time: Double($0) * 5, text: "line \($0)", translation: "译文 \($0)")
        }, source: .netease, isSynced: true)
    }

    private func romanised() -> Lyrics {
        Lyrics(lines: (0..<8).map {
            LyricLine(time: Double($0) * 5, text: "line \($0)", romaji: "roma \($0)")
        }, source: .netease, isSynced: true)
    }

    private func score(_ lyrics: Lyrics, _ secondary: SecondaryLine) -> Int {
        LyricsManager.scoreLyrics(lyrics, langPref: .any, trackName: "t", trackArtist: "a",
                                  secondary: secondary)
    }

    func testScoringIsUnchangedWhenSecondLineIsNextLine() {
        XCTAssertEqual(score(translated(), .nextLine), score(untranslated(), .nextLine))
    }

    func testTranslatedResultOutscoresUntranslatedWhenTranslationSelected() {
        XCTAssertGreaterThan(score(translated(), .translation), score(untranslated(), .translation))
    }

    func testRomajiEarnsNoBonusInTranslationMode() {
        XCTAssertEqual(score(romanised(), .translation), score(untranslated(), .translation))
    }

    func testRomajiResultOutscoresUntranslatedWhenRomajiSelected() {
        XCTAssertGreaterThan(score(romanised(), .romaji), score(untranslated(), .romaji))
    }

    /// The regression this feature lives or dies on.
    ///
    /// `LyricsManager` cancels the whole task group the moment any provider
    /// reaches `maxScore`. An untranslated LRCLIB result already reaches the old
    /// ceiling of 5, so with the bonus added but the ceiling left alone, LRCLIB
    /// wins the race and cancels NetEase *before it answers* — the feature would
    /// do nothing, intermittently, looking exactly like a network flake.
    func testAPerfectUntranslatedResultCannotTriggerEarlyCancellation() {
        let ceiling = LyricsManager.maxScore(for: .translation)
        XCTAssertLessThan(score(untranslated(), .translation), ceiling)
    }

    func testATranslatedResultStillTriggersEarlyCancellation() {
        XCTAssertGreaterThanOrEqual(score(translated(), .translation),
                                    LyricsManager.maxScore(for: .translation))
    }

    func testCeilingIsUnchangedWhenSecondLineIsNextLine() {
        XCTAssertEqual(LyricsManager.maxScore(for: .nextLine), 5)
        XCTAssertGreaterThanOrEqual(score(untranslated(), .nextLine),
                                    LyricsManager.maxScore(for: .nextLine))
    }
}

/// Cache identity. The provider chosen for a track now depends on which second
/// line the user asked for, so the cache key has to depend on it too.
@MainActor
final class LyricsCacheKeyTests: XCTestCase {

    /// Anyone who never touches this setting keeps their existing cache: the
    /// default mode's key is the bare track ID, exactly as before.
    func testDefaultModeKeyIsTheBareTrackID() {
        XCTAssertEqual(LyricsManager.cacheKey(trackID: "spotify:track:abc", secondary: .nextLine),
                       "spotify:track:abc")
    }

    /// Without this, switching to Chinese Translation would keep serving the
    /// untranslated result cached under the old mode — for every track already
    /// played, forever.
    func testEachModeGetsItsOwnKey() {
        let keys = SecondaryLine.allCases.map {
            LyricsManager.cacheKey(trackID: "spotify:track:abc", secondary: $0)
        }
        XCTAssertEqual(Set(keys).count, SecondaryLine.allCases.count)
    }

    func testKeysStayDistinctBetweenTracks() {
        XCTAssertNotEqual(LyricsManager.cacheKey(trackID: "a", secondary: .translation),
                          LyricsManager.cacheKey(trackID: "b", secondary: .translation))
    }
}
