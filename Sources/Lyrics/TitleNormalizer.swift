import Foundation

/// Normalizes track titles for lyrics lookup.
///
/// Spotify and Apple Music decorate titles with qualifiers the lyrics databases don't
/// index — `- Remastered 2011`, `- 粵語版`, `(feat. X)`. Searching with the decorated
/// string misses entirely (LRCLIB returns zero rows), so providers search the normalized
/// title and `SearchMatchScore` compares normalized forms on both sides.
///
/// Stripping is keyword-gated: a dash suffix is only dropped when it looks like a
/// qualifier, so titles where the dash is meaningful ("Marry Me - A Little") survive.
public enum TitleNormalizer {

    /// Latin qualifier words, matched on word boundaries against a lowercased suffix.
    private static let latinQualifiers = """
    \\b(remaster(ed)?|re-?recorded|radio edit|single version|album version|extended|\
    original mix|club mix|live|acoustic|unplugged|demo|bonus|instrumental|karaoke|\
    remix|mix|edit|version|cover|explicit|clean|deluxe|anniversary|edition|\
    soundtrack|ost|theme|reprise|interlude|mono|stereo|feat\\.?|ft\\.?|with)\\b
    """

    /// CJK qualifier markers. `版` alone covers 粵語版 / 国语版 / 完整版 / 抖音版.
    private static let cjkQualifiers =
        "版|現場|现场|伴奏|純音樂|纯音乐|翻自|重製|重制|原聲|原声|主題曲|主题曲|演唱會|演唱会|片段"

    /// True when a dash suffix or parenthetical looks like a qualifier rather than
    /// part of the actual title.
    static func isQualifier(_ fragment: String) -> Bool {
        let text = fragment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        if text.range(of: cjkQualifiers, options: .regularExpression) != nil { return true }
        return text.range(of: latinQualifiers, options: .regularExpression) != nil
    }

    public static func normalize(_ title: String) -> String {
        var result = stripQualifierParentheticals(title)
        result = stripQualifierDashSuffixes(result)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never normalize a title out of existence.
        return trimmed.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }

    /// Removes `(feat. X)`, `(粤语版)`, `[Live]` — any bracketed qualifier.
    private static func stripQualifierParentheticals(_ title: String) -> String {
        let pattern = "\\s*[\\(（\\[]([^\\)）\\]]*)[\\)）\\]]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return title }

        var result = title
        var searchRange = NSRange(result.startIndex..., in: result)
        while let match = regex.firstMatch(in: result, range: searchRange) {
            guard let full = Range(match.range, in: result),
                  let inner = Range(match.range(at: 1), in: result) else { break }
            if isQualifier(String(result[inner])) {
                result.removeSubrange(full)
            } else {
                // Keep it, and resume scanning after this group.
                guard match.range.upperBound < (result as NSString).length else { break }
                searchRange = NSRange(location: match.range.upperBound,
                                      length: (result as NSString).length - match.range.upperBound)
                continue
            }
            searchRange = NSRange(result.startIndex..., in: result)
        }
        return result
    }

    /// Removes trailing ` - Qualifier` segments, repeatedly (`A - Live - Remastered`).
    private static func stripQualifierDashSuffixes(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Require whitespace around the dash so hyphenated words ("Jack-in-the-box") survive.
        let separators = [" - ", " – ", " — "]
        var didStrip = true
        while didStrip {
            didStrip = false
            for separator in separators {
                guard let range = result.range(of: separator, options: .backwards) else { continue }
                let suffix = String(result[range.upperBound...])
                if isQualifier(suffix) {
                    result = String(result[..<range.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    didStrip = true
                    break
                }
            }
        }
        return result
    }

    /// Comparison key: normalized, Traditional→Simplified folded, case/width/diacritic folded.
    ///
    /// Spotify reports Traditional Han (執迷不悔) while NetEase reports Simplified (执迷不悔);
    /// without this fold the identical track scores zero on name.
    static func matchKey(_ text: String) -> String {
        let normalized = normalize(text)
        let simplified = normalized.applyingTransform(
            StringTransform(rawValue: "Hant-Hans"), reverse: false
        ) ?? normalized
        return simplified
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
