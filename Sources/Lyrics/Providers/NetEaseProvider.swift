import Foundation

public struct NetEaseProvider: LyricsProvider {
    public let source: LyricsSource = .netease

    public func fetch(track: TrackInfo) async throws -> Lyrics? {
        // Step 1: Search for the song
        guard let songID = try await searchSong(track: track) else { return nil }

        // Step 2: Get lyrics by song ID
        return try await fetchLyrics(songID: songID)
    }

    private func searchSong(track: TrackInfo) async throws -> Int? {
        guard let url = URL(string: "https://music.163.com/api/search/get") else { return nil }

        let query = "\(track.name) \(track.artist)"
        let bodyString = "s=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&type=1&limit=5&offset=0"

        var request = providerRequest(url: url, userAgent: "Mozilla/5.0")
        request.httpMethod = "POST"
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]] else { return nil }

        // Find best match by duration
        let targetDuration = track.duration * 1000  // NetEase uses ms
        var bestMatch: (id: Int, diff: Double)?

        for song in songs {
            guard let id = song["id"] as? Int,
                  let duration = song["duration"] as? Double else { continue }

            let diff = abs(duration - targetDuration)
            if bestMatch == nil || diff < bestMatch!.diff {
                bestMatch = (id, diff)
            }
        }

        // Only accept if duration difference is within 5 seconds
        if let match = bestMatch, match.diff < 5000 {
            return match.id
        }
        return nil
    }

    private func fetchLyrics(songID: Int) async throws -> Lyrics? {
        guard let url = URL(string: "https://music.163.com/api/song/lyric?id=\(songID)&lv=1") else { return nil }

        var request = providerRequest(url: url, userAgent: "Mozilla/5.0")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lrc = json["lrc"] as? [String: Any],
              let lyricStr = lrc["lyric"] as? String else { return nil }

        let lines = LRCParser.parse(lyricStr)
        if !lines.isEmpty {
            return Lyrics(lines: lines, source: .netease, isSynced: true)
        }

        return nil
    }
}
