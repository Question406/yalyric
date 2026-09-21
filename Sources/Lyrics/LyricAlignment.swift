import Foundation

/// Pairs NetEase's parallel `tlyric` (translation) and `romalrc` (romaji) payloads
/// onto the original lyric lines.
///
/// NetEase writes all three payloads from the same source, so their timestamps
/// agree — a probe of a real track matched 42 of 42 translation lines exactly.
/// Matching is still done through a tolerance window rather than on equality:
/// the three payloads are parsed independently, and `LRCParser`'s centisecond
/// branch reads `[00:12.0]` as 12.03s but `[00:12.00]` as 12.00s. An exact key
/// would silently drop every line whose notation happened to differ, leaving the
/// user with no translation and no error.
enum LyricAlignment {

    /// Wide enough to absorb notation drift between payloads, far narrower than
    /// the gap between two sung lines.
    static let toleranceSeconds: TimeInterval = 0.05

    static func merge(original: [LyricLine],
                      translation: [LyricLine],
                      romaji: [LyricLine]) -> [LyricLine] {
        guard !translation.isEmpty || !romaji.isEmpty else { return original }
        return original.map { line in
            LyricLine(
                time: line.time,
                text: line.text,
                translation: alternate(for: line, in: translation),
                romaji: alternate(for: line, in: romaji)
            )
        }
    }

    /// The nearest candidate inside the tolerance window, or nil when there is
    /// nothing worth showing. A candidate identical to the original is dropped:
    /// NetEase returns the source text as its own "translation" often enough
    /// that displaying it would just look like a rendering bug.
    private static func alternate(for line: LyricLine, in candidates: [LyricLine]) -> String? {
        let nearest = candidates
            .filter { abs($0.time - line.time) <= toleranceSeconds }
            .min { abs($0.time - line.time) < abs($1.time - line.time) }
        guard let nearest else { return nil }

        let text = nearest.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != line.text else { return nil }
        return text
    }
}
