import Foundation

struct TrackInfo: Equatable {
    let id: String           // spotify:track:XXXX
    let name: String
    let artist: String
    let album: String
    let duration: TimeInterval  // seconds

    /// Extract the Spotify track ID (without the spotify:track: prefix)
    var spotifyID: String {
        if id.hasPrefix("spotify:track:") {
            return String(id.dropFirst("spotify:track:".count))
        }
        return id
    }
}
