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
        // Raw title first, then normalized; finally the normalized title alone, which
        // helps when Spotify's romanised artist ("Jess Lee") isn't how NetEase indexes it.
        var queries = track.searchTitles.map { "\($0) \(track.artist)" }
        if let normalized = track.searchTitles.last, !queries.contains(normalized) {
            queries.append(normalized)
        }
        for query in queries {
            if let id = try await searchSong(track: track, query: query) { return id }
        }
        return nil
    }

    private func searchSong(track: TrackInfo, query: String) async throws -> Int? {
        guard let url = URL(string: "https://music.163.com/api/search/get") else { return nil }

        let bodyString = "s=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&type=1&limit=5&offset=0"

        var request = providerRequest(url: url, userAgent: "Mozilla/5.0")
        request.httpMethod = "POST"
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")

        let (data, response) = try await providerSession.data(for: request)
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
                provider: source.rawValue,
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
        // tv=1 asks for the translation, rv=1 for the romaji transliteration.
        // Both arrive in the same response as the original, written from the
        // same source and sharing its timestamps.
        guard let url = URL(string: "https://music.163.com/api/song/lyric?id=\(songID)&lv=1&tv=1&rv=1")
        else { return nil }

        var request = providerRequest(url: url, userAgent: "Mozilla/5.0")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")

        let (data, response) = try await providerSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Self.lyrics(from: json)
    }

    /// Decodes the three parallel payloads into one set of lines. Split out from
    /// the network call so the pairing is testable without a request.
    ///
    /// `tlyric` and `romalrc` are routinely present but empty — an instrumental,
    /// or a track nobody has translated — which is not an error, just a track
    /// with no second line to offer.
    static func lyrics(from json: [String: Any]) -> Lyrics? {
        func parse(_ key: String) -> [LyricLine] {
            guard let payload = json[key] as? [String: Any],
                  let text = payload["lyric"] as? String else { return [] }
            return LRCParser.parse(text)
        }

        let original = parse("lrc")
        guard !original.isEmpty else { return nil }

        let lines = LyricAlignment.merge(original: original,
                                         translation: parse("tlyric"),
                                         romaji: parse("romalrc"))
        return Lyrics(lines: lines, source: .netease, isSynced: true)
    }
}
