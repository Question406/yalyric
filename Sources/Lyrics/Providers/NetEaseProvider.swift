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

        // Score each result using shared validation
        let scored: [(id: Int, score: Int, durationDiff: Double)] = songs.compactMap { song in
            guard let id = song["id"] as? Int,
                  let duration = song["duration"] as? Double else { return nil }

            // NetEase has artists as an array of {name: ...}
            let artistName = (song["artists"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String }
                .joined(separator: " ")

            let score = SearchMatchScore.score(
                resultName: song["name"] as? String,
                resultArtist: artistName,
                resultDurationMs: duration,
                track: track
            )

            return (id, score, abs(duration - track.duration * 1000))
        }

        let best = scored
            .filter { $0.score >= SearchMatchScore.minimumScore }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.durationDiff < $1.durationDiff }
            .first

        return best?.id
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
