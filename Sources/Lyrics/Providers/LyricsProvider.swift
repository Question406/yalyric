import Foundation

public protocol LyricsProvider {
    var source: LyricsSource { get }
    func fetch(track: TrackInfo) async throws -> Lyrics?
}

let providerTimeout: TimeInterval = 5.0

var durationToleranceSeconds: Double {
    AppConfig.get(AppConfig.Sources.durationTolerance)
}

func providerRequest(url: URL, userAgent: String = "yalyric/1.0") -> URLRequest {
    var request = URLRequest(url: url)
    request.timeoutInterval = providerTimeout
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    return request
}

// MARK: - Search Result Validation

/// Shared scoring for search results across all providers.
/// Returns a score (0-8). Results with score < 3 should be rejected.
struct SearchMatchScore {
    static let minimumScore = 3  // at least name OR artist must match

    /// Score a search result against the expected track.
    /// - name match: +3 (contains-based, case-insensitive)
    /// - artist match: +3 (contains-based, case-insensitive)
    /// - duration match: +2 (within configured tolerance)
    static func score(
        resultName: String?,
        resultArtist: String?,
        resultDurationMs: Double?,
        track: TrackInfo
    ) -> Int {
        let trackNameLower = track.name.lowercased()
        let artistLower = track.artist.lowercased()
        var score = 0

        let nameMatch: Bool
        if let name = resultName?.lowercased(),
           name.contains(trackNameLower) || trackNameLower.contains(name) {
            score += 3
            nameMatch = true
        } else {
            nameMatch = false
        }

        let artistMatch: Bool
        if let artist = resultArtist?.lowercased(),
           artist.contains(artistLower) || artistLower.contains(artist) {
            score += 3
            artistMatch = true
        } else {
            artistMatch = false
        }

        var durationDiff: Double = -1
        if let durationMs = resultDurationMs {
            durationDiff = abs(durationMs / 1000.0 - track.duration)
            if durationDiff < durationToleranceSeconds {
                score += 2
            }
        }

        if score < minimumScore {
            YalyricLog.info("[yalyric]     Match rejected: '\(resultName ?? "?")' by '\(resultArtist ?? "?")' "
                + "(name: \(nameMatch), artist: \(artistMatch), dur diff: \(String(format: "%.1fs", durationDiff)), score: \(score))")
        }

        return score
    }
}
