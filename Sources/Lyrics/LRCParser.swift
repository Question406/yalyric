import Foundation

public struct LyricLine: Equatable {
    public let time: TimeInterval  // seconds
    public let text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public enum LyricsSource: String {
    case lrclib
    case spotify
    case musixmatch
    case netease
    case plain  // unsynced plain text
}

public struct Lyrics {
    public let lines: [LyricLine]  // sorted by time
    public let source: LyricsSource
    public let isSynced: Bool

    public init(lines: [LyricLine], source: LyricsSource, isSynced: Bool) {
        self.lines = lines
        self.source = source
        self.isSynced = isSynced
    }

    /// Find the index of the current line for the given playback position
    public func currentLineIndex(at position: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        if !isSynced { return nil }

        // Binary search for the last line whose time <= position
        var low = 0
        var high = lines.count - 1
        var result = -1

        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return result >= 0 ? result : nil
    }
}

public struct LRCParser {
    private static let timeTagRegex = try! NSRegularExpression(
        pattern: #"^\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]"#
    )

    public static func parse(_ lrcString: String) -> [LyricLine] {
        var lines: [LyricLine] = []

        for rawLine in lrcString.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            var searchStr = trimmed
            var times: [TimeInterval] = []

            // Extract all time tags from the beginning of the line
            while true {
                let range = NSRange(searchStr.startIndex..., in: searchStr)
                guard let match = timeTagRegex.firstMatch(in: searchStr, range: range) else { break }

                let minutesRange = Range(match.range(at: 1), in: searchStr)!
                let secondsRange = Range(match.range(at: 2), in: searchStr)!

                let minutes = Double(searchStr[minutesRange]) ?? 0
                let seconds = Double(searchStr[secondsRange]) ?? 0

                var ms: Double = 0
                if match.range(at: 3).location != NSNotFound,
                   let msRange = Range(match.range(at: 3), in: searchStr) {
                    let msString = String(searchStr[msRange])
                    if msString.count <= 2 {
                        ms = (Double(msString) ?? 0) * 10  // centiseconds
                    } else {
                        ms = Double(msString) ?? 0  // milliseconds
                    }
                }

                let time = minutes * 60.0 + seconds + ms / 1000.0
                times.append(time)

                let fullMatchRange = Range(match.range, in: searchStr)!
                searchStr = String(searchStr[fullMatchRange.upperBound...])
            }

            guard !times.isEmpty else { continue }
            let text = searchStr.trimmingCharacters(in: .whitespaces)

            for time in times {
                lines.append(LyricLine(time: time, text: text))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }

    public static func parsePlain(_ text: String) -> [LyricLine] {
        let rawLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return rawLines.enumerated().map { index, line in
            LyricLine(time: Double(index), text: line)
        }
    }
}
