import Foundation

public struct MusixmatchProvider: LyricsProvider {
    public let source: LyricsSource = .musixmatch

    // Persisted to UserDefaults — Musixmatch captcha-blocks token re-auth after first request
    private static var cachedToken: String? = {
        let t = AppConfig.get(AppConfig.Sources.musixmatchToken)
        return t.isEmpty ? nil : t
    }()
    private static var tokenExpiry: Date? = {
        let ts = AppConfig.get(AppConfig.Sources.musixmatchTokenExpiry)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }()

    public func fetch(track: TrackInfo) async throws -> Lyrics? {
        guard let token = try await getToken() else { return nil }

        var components = URLComponents(string: "https://apic-desktop.musixmatch.com/ws/1.1/macro.subtitles.get")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "namespace", value: "lyrics_richsynced"),
            URLQueryItem(name: "subtitle_format", value: "lrc"),
            URLQueryItem(name: "q_track", value: track.name),
            URLQueryItem(name: "q_artist", value: track.artist),
            URLQueryItem(name: "q_album", value: track.album),
            URLQueryItem(name: "q_duration", value: String(Int(track.duration))),
            URLQueryItem(name: "usertoken", value: token),
            URLQueryItem(name: "app_id", value: "web-desktop-app-v1.0"),
        ]

        guard let url = components.url else { return nil }
        let request = providerRequest(url: url, userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        let (lyrics, commontrackId) = try parseResponse(data, track: track)
        guard var lyrics = lyrics else { return nil }

        // Try to fetch richsync (word-level timing) if we have a commontrack_id
        if lyrics.isSynced, let ctId = commontrackId {
            if let richLines = try? await fetchRichsync(commontrackId: ctId, duration: track.duration, token: token) {
                YalyricLog.info("[musixmatch] Got richsync with \(richLines.count) lines, word-level timing available")
                lyrics = Lyrics(lines: richLines, source: .musixmatch, isSynced: true)
            } else {
                YalyricLog.info("[musixmatch] No richsync available (commontrack_id=\(ctId)), using line-level + estimated word timing")
            }
        } else if lyrics.isSynced {
            YalyricLog.info("[musixmatch] No commontrack_id found, using line-level + estimated word timing")
        }

        return lyrics
    }

    private func getToken() async throws -> String? {
        // Return cached token if still valid
        if let token = Self.cachedToken,
           let expiry = Self.tokenExpiry,
           Date() < expiry {
            return token
        }

        guard let url = URL(string: "https://apic-desktop.musixmatch.com/ws/1.1/token.get?app_id=web-desktop-app-v1.0") else { return nil }

        let request = providerRequest(url: url, userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let body = message["body"] as? [String: Any],
              let token = body["user_token"] as? String else { return nil }

        let expiry = Date().addingTimeInterval(3600)  // 1 hour — re-auth is captcha-blocked
        Self.cachedToken = token
        Self.tokenExpiry = expiry
        AppConfig.set(AppConfig.Sources.musixmatchToken, token)
        AppConfig.set(AppConfig.Sources.musixmatchTokenExpiry, expiry.timeIntervalSince1970)
        return token
    }

    /// Returns (lyrics, commontrack_id). The commontrack_id is used for the separate richsync call.
    private func parseResponse(_ data: Data, track: TrackInfo) throws -> (Lyrics?, Int?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let body = message["body"] as? [String: Any],
              let macroCalls = body["macro_calls"] as? [String: Any] else { return (nil, nil) }

        // Extract commontrack_id and validate matched track
        var commontrackId: Int?
        if let matcherGet = macroCalls["matcher.track.get"] as? [String: Any],
           let matchMsg = matcherGet["message"] as? [String: Any],
           let matchBody = matchMsg["body"] as? [String: Any],
           let matchTrack = matchBody["track"] as? [String: Any] {
            commontrackId = matchTrack["commontrack_id"] as? Int

            let score = SearchMatchScore.score(
                resultName: matchTrack["track_name"] as? String,
                resultArtist: matchTrack["artist_name"] as? String,
                resultDurationMs: (matchTrack["track_length"] as? Double).map { $0 * 1000 },
                track: track
            )
            if score < SearchMatchScore.minimumScore {
                YalyricLog.info("[musixmatch] Rejected: matched '\(matchTrack["track_name"] ?? "")' by '\(matchTrack["artist_name"] ?? "")' (score \(score))")
                return (nil, nil)
            }
        }

        // Check if richsync is already in the macro response
        if let richsyncGet = macroCalls["track.richsync.get"] as? [String: Any],
           let rsMessage = richsyncGet["message"] as? [String: Any],
           let rsBody = rsMessage["body"] as? [String: Any],
           let richsyncList = rsBody["richsync_list"] as? [[String: Any]],
           let first = richsyncList.first,
           let richsync = first["richsync"] as? [String: Any],
           let richsyncBody = richsync["richsync_body"] as? String {
            let lines = RichsyncParser.parse(richsyncBody)
            if !lines.isEmpty {
                YalyricLog.info("[musixmatch] Got richsync from macro response with \(lines.count) lines")
                return (Lyrics(lines: lines, source: .musixmatch, isSynced: true), commontrackId)
            }
        }

        // Try synced subtitles
        if let subtitleGet = macroCalls["track.subtitles.get"] as? [String: Any],
           let subMessage = subtitleGet["message"] as? [String: Any],
           let subBody = subMessage["body"] as? [String: Any],
           let subtitleList = subBody["subtitle_list"] as? [[String: Any]],
           let first = subtitleList.first,
           let subtitle = first["subtitle"] as? [String: Any],
           let subtitleBody = subtitle["subtitle_body"] as? String {
            let lines = LRCParser.parse(subtitleBody)
            if !lines.isEmpty {
                return (Lyrics(lines: lines, source: .musixmatch, isSynced: true), commontrackId)
            }
        }

        // Fallback to plain lyrics
        if let lyricsGet = macroCalls["track.lyrics.get"] as? [String: Any],
           let lyrMessage = lyricsGet["message"] as? [String: Any],
           let lyrBody = lyrMessage["body"] as? [String: Any],
           let lyrics = lyrBody["lyrics"] as? [String: Any],
           let lyricsBody = lyrics["lyrics_body"] as? String,
           !lyricsBody.isEmpty {
            let lines = LRCParser.parsePlain(lyricsBody)
            return (Lyrics(lines: lines, source: .musixmatch, isSynced: false), commontrackId)
        }

        return (nil, nil)
    }

    /// Fetch richsync (word-level timing) using a separate API call.
    private func fetchRichsync(commontrackId: Int, duration: TimeInterval, token: String) async throws -> [LyricLine]? {
        var components = URLComponents(string: "https://apic-desktop.musixmatch.com/ws/1.1/track.richsync.get")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "subtitle_format", value: "mxm"),
            URLQueryItem(name: "commontrack_id", value: String(commontrackId)),
            URLQueryItem(name: "q_duration", value: String(Int(duration))),
            URLQueryItem(name: "usertoken", value: token),
            URLQueryItem(name: "app_id", value: "web-desktop-app-v1.0"),
        ]

        guard let url = components.url else { return nil }
        let request = providerRequest(url: url, userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let msgBody = message["body"] as? [String: Any],
              let richsync = msgBody["richsync"] as? [String: Any],
              let richsyncBody = richsync["richsync_body"] as? String else {
            return nil
        }

        let lines = RichsyncParser.parse(richsyncBody)
        return lines.isEmpty ? nil : lines
    }
}

/// Parses Musixmatch richsync JSON into LyricLines with word-level timing.
enum RichsyncParser {
    static func parse(_ richsyncBody: String) -> [LyricLine] {
        guard let data = richsyncBody.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var lines: [LyricLine] = []
        for entry in entries {
            guard let ts = entry["ts"] as? Double,
                  let wordArray = entry["l"] as? [[String: Any]],
                  !wordArray.isEmpty else {
                continue
            }

            var words: [WordTiming] = []
            var fullText = ""
            for w in wordArray {
                guard let c = w["c"] as? String,
                      let o = w["o"] as? Double else { continue }
                words.append(WordTiming(text: c, offset: o))
                fullText += c
            }

            guard !words.isEmpty else { continue }
            let text = fullText.trimmingCharacters(in: .whitespaces)
            lines.append(LyricLine(time: ts, text: text, words: words))
        }

        return lines.sorted { $0.time < $1.time }
    }
}
