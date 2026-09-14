import Foundation

public protocol LyricsProvider {
    var source: LyricsSource { get }
    func fetch(track: TrackInfo) async throws -> Lyrics?
}

let providerTimeout: TimeInterval = 5.0

var durationToleranceSeconds: Double {
    AppConfig.get(AppConfig.Sources.durationTolerance)
}

/// Shared session for all lyrics providers.
///
/// Cookies are disabled deliberately. NetEase sets an `NMTID` cookie on first contact;
/// once a caller starts returning it, `music.163.com/api/search/get` throttles them —
/// it ignores the POST body entirely and answers with ten arbitrary popular songs
/// instead of the query results. Because the response is HTTP 200 with a well-formed
/// body, the provider cannot tell it apart from a genuine miss.
let providerSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.httpCookieStorage = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.urlCache = nil
    config.timeoutIntervalForRequest = providerTimeout
    return URLSession(configuration: config)
}()

extension TrackInfo {
    /// Title variants to try against search APIs, most specific first. Providers fall
    /// back to the normalized form because lyrics databases index bare titles.
    var searchTitles: [String] {
        let normalized = TitleNormalizer.normalize(name)
        return normalized == name || normalized.isEmpty ? [name] : [name, normalized]
    }
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

    static func rejectionMessage(
        provider: String, resultName: String?, resultArtist: String?,
        durationDiff: Double, nameMatch: Bool, artistMatch: Bool, score: Int
    ) -> String {
        "[yalyric]     [\(provider)] Match rejected: '\(resultName ?? "?")' by '\(resultArtist ?? "?")' "
            + "(name: \(nameMatch), artist: \(artistMatch), dur diff: \(String(format: "%.1fs", durationDiff)), score: \(score))"
    }

    /// Score a search result against the expected track.
    /// - name match: +3 (contains-based, on normalized/Han-folded keys)
    /// - artist match: +3 (same)
    /// - duration match: +2 (within configured tolerance)
    ///
    /// Duration alone deliberately cannot reach `minimumScore`: a wrong song frequently
    /// lands inside the tolerance window, so a duration hit must be corroborated.
    static func score(
        provider: String,
        resultName: String?,
        resultArtist: String?,
        resultDurationMs: Double?,
        track: TrackInfo
    ) -> Int {
        let trackNameKey = TitleNormalizer.matchKey(track.name)
        let artistKey = TitleNormalizer.matchKey(track.artist)
        var score = 0

        let nameMatch = matches(resultName, trackNameKey)
        if nameMatch { score += 3 }

        let artistMatch = matches(resultArtist, artistKey)
        if artistMatch { score += 3 }

        var durationDiff: Double = -1
        if let durationMs = resultDurationMs {
            durationDiff = abs(durationMs / 1000.0 - track.duration)
            if durationDiff < durationToleranceSeconds {
                score += 2
            }
        }

        if score < minimumScore {
            YalyricLog.info(rejectionMessage(
                provider: provider, resultName: resultName, resultArtist: resultArtist,
                durationDiff: durationDiff, nameMatch: nameMatch, artistMatch: artistMatch, score: score))
        }

        return score
    }

    /// Containment on normalized keys. Empty keys never match — otherwise a provider
    /// returning a blank artist would match every track.
    ///
    /// Containment is asymmetric on purpose. A result may freely *contain* the track key,
    /// since providers decorate names ("执迷不悔(国)" ⊃ "执迷不悔"). But when the track name
    /// is the longer side, the result must be a *prefix* of it: bilingual titles fuse two
    /// names together ("甲乙丙丁Strangers"), and plain containment let an unrelated English
    /// song called "Strangers" match a Cantonese track.
    private static func matches(_ candidate: String?, _ trackKey: String) -> Bool {
        guard let candidate, !trackKey.isEmpty else { return false }
        let candidateKey = TitleNormalizer.matchKey(candidate)
        guard !candidateKey.isEmpty else { return false }
        if candidateKey.contains(trackKey) { return true }
        if trackKey.contains(candidateKey) { return trackKey.hasPrefix(candidateKey) }
        return false
    }
}
