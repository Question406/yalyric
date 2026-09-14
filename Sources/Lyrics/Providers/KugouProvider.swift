import Foundation

/// Kugou (酷狗音乐) — three unauthenticated calls: song search → lyric candidates → download.
///
/// Added because LRCLIB is thin on Mandarin/Cantonese catalogue and the Spotify and
/// Musixmatch providers are both unusable (see their files). Kugou needs no token,
/// no cookie and no captcha, and returns line-synced LRC.
public struct KugouProvider: LyricsProvider {
    public let source: LyricsSource = .kugou

    public init() {}

    private struct Candidate {
        let id: String
        let accessKey: String
    }

    public func fetch(track: TrackInfo) async throws -> Lyrics? {
        for query in queries(for: track) {
            guard let hash = try await searchHash(query: query, track: track),
                  let candidate = try await lyricCandidate(hash: hash) else { continue }
            if let lyrics = try await downloadLyrics(candidate) {
                return lyrics
            }
        }
        return nil
    }

    /// Title+artist first, then the bare title — Kugou indexes Chinese artist names, so a
    /// romanised Spotify artist ("Faye Wong") can hurt more than it helps.
    ///
    /// Deliberately capped at two queries: `songsearch.kugou.com` throttles bursts and
    /// then answers every request with `total: 0`, which is indistinguishable from a miss.
    /// The normalized title is used because Kugou indexes bare titles.
    private func queries(for track: TrackInfo) -> [String] {
        let title = track.searchTitles.last ?? track.name
        let withArtist = "\(title) \(track.artist)"
        return title == withArtist ? [title] : [withArtist, title]
    }

    // MARK: - Step 1: song search → FileHash

    private func searchHash(query: String, track: TrackInfo) async throws -> String? {
        var components = URLComponents(string: "https://songsearch.kugou.com/song_search_v2")!
        components.queryItems = [
            URLQueryItem(name: "keyword", value: query),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: "10"),
        ]
        guard let url = components.url else { return nil }

        var request = providerRequest(url: url, userAgent: "Mozilla/5.0")
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await providerSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lists = (json["data"] as? [String: Any])?["lists"] as? [[String: Any]] else { return nil }

        return Self.bestHash(from: lists, track: track)
    }

    /// Picks the best-scoring search result.
    ///
    /// Kugou reports `Duration` in **seconds**; `SearchMatchScore` expects milliseconds.
    static func bestHash(from songs: [[String: Any]], track: TrackInfo) -> String? {
        let scored = songs.compactMap { song -> (hash: String, score: Int, diff: Double)? in
            guard let hash = song["FileHash"] as? String, !hash.isEmpty else { return nil }
            let seconds = (song["Duration"] as? NSNumber)?.doubleValue
            let score = SearchMatchScore.score(
                provider: "kugou",
                resultName: stripHighlight(song["SongName"] as? String),
                resultArtist: stripHighlight(song["SingerName"] as? String),
                resultDurationMs: seconds.map { $0 * 1000 },
                track: track
            )
            let diff = seconds.map { abs($0 - track.duration) } ?? .greatestFiniteMagnitude
            return (hash, score, diff)
        }
        .filter { $0.score >= SearchMatchScore.minimumScore }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.diff < $1.diff }

        return scored.first?.hash
    }

    /// Kugou wraps matched terms in `<em>` tags on some search hosts.
    private static func stripHighlight(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "<em>", with: "")
            .replacingOccurrences(of: "</em>", with: "")
    }

    // MARK: - Step 2: hash → lyric candidate (id + accesskey)

    private func lyricCandidate(hash: String) async throws -> Candidate? {
        var components = URLComponents(string: "https://krcs.kugou.com/search")!
        components.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "client", value: "mobi"),
            URLQueryItem(name: "hash", value: hash),
        ]
        guard let url = components.url else { return nil }

        let request = providerRequest(url: url, userAgent: "Mozilla/5.0")
        let (data, response) = try await providerSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let accessKey = first["accesskey"] as? String, !accessKey.isEmpty else { return nil }

        // `id` comes back as a string on some hosts and a number on others.
        let id = (first["id"] as? String) ?? (first["id"] as? NSNumber)?.stringValue
        guard let id, !id.isEmpty else { return nil }

        return Candidate(id: id, accessKey: accessKey)
    }

    // MARK: - Step 3: download the LRC

    private func downloadLyrics(_ candidate: Candidate) async throws -> Lyrics? {
        var components = URLComponents(string: "https://lyrics.kugou.com/download")!
        components.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "id", value: candidate.id),
            URLQueryItem(name: "accesskey", value: candidate.accessKey),
            URLQueryItem(name: "fmt", value: "lrc"),
            URLQueryItem(name: "charset", value: "utf8"),
        ]
        guard let url = components.url else { return nil }

        let request = providerRequest(url: url, userAgent: "Mozilla/5.0")
        let (data, response) = try await providerSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        return Self.parseLyrics(from: data)
    }

    /// Decodes the base64 `content` field into synced lyrics. Metadata tags
    /// (`[ar:]`, `[ti:]`, `[id:]`) carry no timestamp and are dropped by LRCParser.
    static func parseLyrics(from data: Data) -> Lyrics? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? NSNumber)?.intValue == 200,
              let content = json["content"] as? String,
              let decoded = Data(base64Encoded: content),
              let lrc = String(data: decoded, encoding: .utf8) else { return nil }

        let lines = LRCParser.parse(lrc)
        guard !lines.isEmpty else { return nil }
        return Lyrics(lines: lines, source: .kugou, isSynced: true)
    }
}
