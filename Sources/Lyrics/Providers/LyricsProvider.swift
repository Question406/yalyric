import Foundation

public protocol LyricsProvider {
    var source: LyricsSource { get }
    func fetch(track: TrackInfo) async throws -> Lyrics?
}

let providerTimeout: TimeInterval = 5.0

func providerRequest(url: URL, userAgent: String = "yalyric/1.0") -> URLRequest {
    var request = URLRequest(url: url)
    request.timeoutInterval = providerTimeout
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    return request
}
