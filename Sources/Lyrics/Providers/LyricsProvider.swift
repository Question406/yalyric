import Foundation

public protocol LyricsProvider {
    var source: LyricsSource { get }
    func fetch(track: TrackInfo) async throws -> Lyrics?
}
