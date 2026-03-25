import Foundation

public struct TrackInfo: Equatable {
    public let id: String           // spotify:track:XXXX
    public let name: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval  // seconds

    public init(id: String, name: String, artist: String, album: String, duration: TimeInterval) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    /// Extract the Spotify track ID (without the spotify:track: prefix)
    public var spotifyID: String {
        if id.hasPrefix("spotify:track:") {
            return String(id.dropFirst("spotify:track:".count))
        }
        return id
    }
}
