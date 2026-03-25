import Foundation

struct LRCLIBProvider: LyricsProvider {
    let source: LyricsSource = .lrclib

    func fetch(track: TrackInfo) async throws -> Lyrics? {
        // Try exact match first
        if let lyrics = try await fetchExact(track: track) {
            return lyrics
        }
        // Fallback to search
        return try await fetchSearch(track: track)
    }

    private func fetchExact(track: TrackInfo) async throws -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration)))
        ]

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("LyricSync/1.0", forHTTPHeaderField: "User-Agent")

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
        var request = URLRequest(url: url)
        request.setValue("LyricSync/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = results.first else { return nil }

        let resultData = try JSONSerialization.data(withJSONObject: first)
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
