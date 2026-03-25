import Testing
@testable import LyricSyncLib

@Suite("TrackInfo")
struct TrackInfoTests {

    @Test("spotifyID strips spotify:track: prefix")
    func spotifyIDWithPrefix() {
        let track = TrackInfo(
            id: "spotify:track:6rqhFgbbKwnb9MLmUQDhG6",
            name: "Test", artist: "Artist", album: "Album", duration: 200
        )
        #expect(track.spotifyID == "6rqhFgbbKwnb9MLmUQDhG6")
    }

    @Test("spotifyID without prefix returns as-is")
    func spotifyIDWithoutPrefix() {
        let track = TrackInfo(
            id: "6rqhFgbbKwnb9MLmUQDhG6",
            name: "Test", artist: "Artist", album: "Album", duration: 200
        )
        #expect(track.spotifyID == "6rqhFgbbKwnb9MLmUQDhG6")
    }

    @Test("spotifyID with empty string")
    func spotifyIDEmpty() {
        let track = TrackInfo(id: "", name: "Test", artist: "Artist", album: "Album", duration: 200)
        #expect(track.spotifyID == "")
    }

    @Test("Equality comparison")
    func equality() {
        let a = TrackInfo(id: "spotify:track:abc", name: "Song", artist: "Artist", album: "Album", duration: 180)
        let b = TrackInfo(id: "spotify:track:abc", name: "Song", artist: "Artist", album: "Album", duration: 180)
        let c = TrackInfo(id: "spotify:track:xyz", name: "Song", artist: "Artist", album: "Album", duration: 180)

        #expect(a == b)
        #expect(a != c)
    }
}
