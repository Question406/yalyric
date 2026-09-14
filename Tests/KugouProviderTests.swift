import XCTest
@testable import yalyricLib

final class KugouProviderTests: XCTestCase {

    private func track(_ name: String, _ artist: String, _ duration: TimeInterval) -> TrackInfo {
        TrackInfo(id: "spotify:track:test", name: name, artist: artist, album: "", duration: duration)
    }

    private func downloadPayload(status: Int, lrc: String) -> Data {
        let encoded = Data(lrc.utf8).base64EncodedString()
        return Data(#"{"status":\#(status),"fmt":"lrc","content":"\#(encoded)"}"#.utf8)
    }

    // MARK: - Lyrics payload decoding

    func testParsesBase64EncodedLRCPayload() throws {
        let lrc = """
        [id:$00000000]
        [ar:王菲]
        [ti:执迷不悔]
        [00:21.25]这次我重头面对
        [00:24.20]过去和以后
        [00:28.06]人如何自欺再不管这对否
        """
        let lyrics = try XCTUnwrap(KugouProvider.parseLyrics(from: downloadPayload(status: 200, lrc: lrc)))
        XCTAssertEqual(lyrics.source, .kugou)
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.count, 3, "metadata tags must not become lyric lines")
        XCTAssertEqual(lyrics.lines[0].time, 21.25, accuracy: 0.01)
        XCTAssertEqual(lyrics.lines[0].text, "这次我重头面对")
        XCTAssertEqual(lyrics.lines[2].text, "人如何自欺再不管这对否")
    }

    func testRejectsPayloadWithNonOKStatus() throws {
        XCTAssertNil(KugouProvider.parseLyrics(from: downloadPayload(status: 0, lrc: "[00:01.00]hi")))
    }

    func testRejectsPayloadWithNoTimedLines() throws {
        XCTAssertNil(KugouProvider.parseLyrics(from: downloadPayload(status: 200, lrc: "[ar:王菲]\nno timing here")))
    }

    func testRejectsMalformedBase64() throws {
        XCTAssertNil(KugouProvider.parseLyrics(from: Data(#"{"status":200,"content":"!!!not base64!!!"}"#.utf8)))
    }

    // MARK: - Candidate selection

    /// Kugou reports `Duration` in SECONDS, while SearchMatchScore expects milliseconds.
    /// Both candidates share a name and artist, so only correct unit conversion can pick
    /// the right one — and the decoy is deliberately listed first.
    func testPicksCandidateByDurationUsingSecondsUnit() {
        let songs: [[String: Any]] = [
            ["SongName": "执迷不悔", "SingerName": "王菲", "Duration": 999, "FileHash": "DECOYHASH"],
            ["SongName": "执迷不悔", "SingerName": "王菲", "Duration": 273, "FileHash": "RIGHTHASH"],
        ]
        XCTAssertEqual(KugouProvider.bestHash(from: songs, track: track("執迷不悔", "Faye Wong", 273.8)), "RIGHTHASH")
    }

    func testRejectsCandidatesThatDoNotMatchTheTrack() {
        let songs: [[String: Any]] = [
            ["SongName": "演员", "SingerName": "薛之谦", "Duration": 261, "FileHash": "WRONGHASH"],
        ]
        XCTAssertNil(KugouProvider.bestHash(from: songs, track: track("執迷不悔", "Faye Wong", 273.8)))
    }

    func testIgnoresCandidatesMissingAHash() {
        let songs: [[String: Any]] = [
            ["SongName": "执迷不悔", "SingerName": "王菲", "Duration": 273],
        ]
        XCTAssertNil(KugouProvider.bestHash(from: songs, track: track("執迷不悔", "Faye Wong", 273.8)))
    }
}
