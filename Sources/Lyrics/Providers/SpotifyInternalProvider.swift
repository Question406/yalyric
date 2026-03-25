import Foundation

public struct SpotifyInternalProvider: LyricsProvider {
    public let source: LyricsSource = .spotify

    public func fetch(track: TrackInfo) async throws -> Lyrics? {
        let cookie = UserDefaults.standard.string(forKey: "spDCCookie") ?? ""
        guard !cookie.isEmpty else { return nil }

        // Step 1: Get access token using SP_DC cookie
        guard let accessToken = try await getAccessToken(spDC: cookie) else { return nil }

        // Step 2: Fetch lyrics
        let trackID = track.spotifyID
        guard let url = URL(string: "https://spclient.wg.spotify.com/color-lyrics/v2/track/\(trackID)?format=json&market=from_token") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        return try parseSpotifyLyrics(data)
    }

    private func getAccessToken(spDC: String) async throws -> String? {
        guard let url = URL(string: "https://open.spotify.com/get_access_token?reason=transport&productType=web_player") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("sp_dc=\(spDC)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["accessToken"] as? String else { return nil }

        return token
    }

    private func parseSpotifyLyrics(_ data: Data) throws -> Lyrics? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lyricsObj = json["lyrics"] as? [String: Any],
              let linesArray = lyricsObj["lines"] as? [[String: Any]] else { return nil }

        let syncType = lyricsObj["syncType"] as? String

        var lines: [LyricLine] = []
        for lineObj in linesArray {
            guard let startTimeMs = lineObj["startTimeMs"] as? String,
                  let timeMs = Double(startTimeMs),
                  let words = lineObj["words"] as? String else { continue }

            // Skip empty instrumental markers
            let text = words.trimmingCharacters(in: .whitespaces)
            if text == "♪" || text.isEmpty { continue }

            lines.append(LyricLine(time: timeMs / 1000.0, text: text))
        }

        guard !lines.isEmpty else { return nil }

        let isSynced = syncType == "LINE_SYNCED"
        return Lyrics(lines: lines, source: .spotify, isSynced: isSynced)
    }
}
