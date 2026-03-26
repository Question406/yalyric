import Foundation

public struct LRCLIBProvider: LyricsProvider {
    public let source: LyricsSource = .lrclib

    public func fetch(track: TrackInfo) async throws -> Lyrics? {
        // Try without duration first — faster and avoids Spotify's inaccurate durations
        if let lyrics = try await fetchExact(track: track, includeDuration: false) {
            return lyrics
        }
        // Fallback to search (broader matching)
        return try await fetchSearch(track: track)
    }

    private func fetchExact(track: TrackInfo, includeDuration: Bool) async throws -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "album_name", value: track.album),
        ]
        if includeDuration {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(track.duration))))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }
        let request = providerRequest(url: url)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        return try parseLRCLIBResponse(data)
    }

    private func fetchSearch(track: TrackInfo) async throws -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(track.artist) \(track.name)")
        ]

        guard let url = components.url else { return nil }
        let request = providerRequest(url: url)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        // Score results using shared validation + synced lyrics bonus
        let scored = results.map { result -> (result: [String: Any], score: Int) in
            var score = SearchMatchScore.score(
                resultName: result["trackName"] as? String,
                resultArtist: result["artistName"] as? String,
                resultDurationMs: (result["duration"] as? Double).map { $0 * 1000 },
                track: track
            )
            if let synced = result["syncedLyrics"] as? String,
               !synced.isEmpty { score += 1 }
            return (result, score)
        }
        .filter { $0.score >= SearchMatchScore.minimumScore }
        .sorted { $0.score > $1.score }

        guard let best = scored.first else { return nil }

        let resultData = try JSONSerialization.data(withJSONObject: best.result)
        return try parseLRCLIBResponse(resultData)
    }

    private func parseLRCLIBResponse(_ data: Data) throws -> Lyrics? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Prefer synced lyrics
        if let syncedLyrics = json["syncedLyrics"] as? String, !syncedLyrics.isEmpty {
            let lines = LRCParser.parse(syncedLyrics)
            if !lines.isEmpty {
                return Lyrics(lines: lines, source: .lrclib, isSynced: true)
            }
        }

        // Fallback to plain lyrics
        if let plainLyrics = json["plainLyrics"] as? String, !plainLyrics.isEmpty {
            let lines = LRCParser.parsePlain(plainLyrics)
            return Lyrics(lines: lines, source: .plain, isSynced: false)
        }

        return nil
    }
}
