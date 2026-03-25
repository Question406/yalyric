import Foundation

public struct MusixmatchProvider: LyricsProvider {
    public let source: LyricsSource = .musixmatch

    private static var cachedToken: String?
    private static var tokenExpiry: Date?

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
        var request = URLRequest(url: url)
        request.setValue("yalyric/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        return try parseResponse(data)
    }

    private func getToken() async throws -> String? {
        // Return cached token if still valid
        if let token = Self.cachedToken,
           let expiry = Self.tokenExpiry,
           Date() < expiry {
            return token
        }

        guard let url = URL(string: "https://apic-desktop.musixmatch.com/ws/1.1/token.get?app_id=web-desktop-app-v1.0") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("yalyric/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let body = message["body"] as? [String: Any],
              let token = body["user_token"] as? String else { return nil }

        Self.cachedToken = token
        Self.tokenExpiry = Date().addingTimeInterval(600)  // 10 min cache
        return token
    }

    private func parseResponse(_ data: Data) throws -> Lyrics? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let body = message["body"] as? [String: Any],
              let macroCalls = body["macro_calls"] as? [String: Any] else { return nil }

        // Try synced subtitles first
        if let subtitleGet = macroCalls["track.subtitles.get"] as? [String: Any],
           let subMessage = subtitleGet["message"] as? [String: Any],
           let subBody = subMessage["body"] as? [String: Any],
           let subtitleList = subBody["subtitle_list"] as? [[String: Any]],
           let first = subtitleList.first,
           let subtitle = first["subtitle"] as? [String: Any],
           let subtitleBody = subtitle["subtitle_body"] as? String {
            let lines = LRCParser.parse(subtitleBody)
            if !lines.isEmpty {
                return Lyrics(lines: lines, source: .musixmatch, isSynced: true)
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
            return Lyrics(lines: lines, source: .musixmatch, isSynced: false)
        }

        return nil
    }
}
