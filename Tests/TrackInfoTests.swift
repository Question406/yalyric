import XCTest
@testable import yalyricLib

final class TrackInfoTests: XCTestCase {

    func testSpotifyIDWithPrefix() {
        let track = TrackInfo(id: "spotify:track:6rqhFgbbKwnb9MLmUQDhG6", name: "Test", artist: "Artist", album: "Album", duration: 200)
        XCTAssertEqual(track.spotifyID, "6rqhFgbbKwnb9MLmUQDhG6")
    }

    func testSpotifyIDWithoutPrefix() {
        let track = TrackInfo(id: "6rqhFgbbKwnb9MLmUQDhG6", name: "Test", artist: "Artist", album: "Album", duration: 200)
        XCTAssertEqual(track.spotifyID, "6rqhFgbbKwnb9MLmUQDhG6")
    }

    func testSpotifyIDEmpty() {
        let track = TrackInfo(id: "", name: "Test", artist: "Artist", album: "Album", duration: 200)
        XCTAssertEqual(track.spotifyID, "")
    }

    func testEquality() {
        let a = TrackInfo(id: "spotify:track:abc", name: "Song", artist: "Artist", album: "Album", duration: 180)
        let b = TrackInfo(id: "spotify:track:abc", name: "Song", artist: "Artist", album: "Album", duration: 180)
        let c = TrackInfo(id: "spotify:track:xyz", name: "Song", artist: "Artist", album: "Album", duration: 180)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
