import Foundation
import Combine

@MainActor
public class SyncEngine: ObservableObject {
    @Published public var currentLineIndex: Int = -1
    @Published public var currentLine: String = ""
    @Published public var nextLine: String = ""
    @Published public var progress: Double = 0  // 0-1 within current line
    @Published public var wordProgresses: [Double] = []
    @Published public var currentWords: [String] = []

    /// Manual offset in seconds. Positive = lyrics appear earlier, negative = later.
    public var offset: TimeInterval = 0

    private var lyrics: Lyrics?
    private var estimatedTimingsCache: (index: Int, timings: [WordTiming])? = nil

    public init() {}

    public var allLines: [LyricLine] {
        lyrics?.lines ?? []
    }

    public var isSynced: Bool {
        lyrics?.isSynced ?? false
    }

    public func setLyrics(_ lyrics: Lyrics?) {
        self.lyrics = lyrics
        currentLineIndex = -1
        currentLine = ""
        nextLine = ""
        progress = 0
        wordProgresses = []
        currentWords = []
        estimatedTimingsCache = nil
    }

    public func update(position: TimeInterval) {
        let adjustedPosition = position + offset

        guard let lyrics = lyrics, !lyrics.lines.isEmpty else {
            currentLineIndex = -1
            currentLine = ""
            nextLine = ""
            progress = 0
            wordProgresses = []
            currentWords = []
            return
        }

        guard lyrics.isSynced else {
            // For unsynced lyrics, don't try to sync
            if currentLineIndex == -1 {
                currentLineIndex = 0
                currentLine = lyrics.lines.first?.text ?? ""
                nextLine = lyrics.lines.count > 1 ? lyrics.lines[1].text : ""
            }
            wordProgresses = []
            currentWords = []
            return
        }

        guard let index = lyrics.currentLineIndex(at: adjustedPosition) else {
            // Before first lyric line
            currentLineIndex = -1
            currentLine = ""
            nextLine = lyrics.lines.first?.text ?? ""
            progress = 0
            wordProgresses = []
            currentWords = []
            return
        }

        if index != currentLineIndex {
            currentLineIndex = index
            currentLine = lyrics.lines[index].text
            nextLine = (index + 1 < lyrics.lines.count) ? lyrics.lines[index + 1].text : ""
        }

        // Calculate progress within current line
        let lineStart = lyrics.lines[index].time
        let lineEnd = (index + 1 < lyrics.lines.count) ? lyrics.lines[index + 1].time : lyrics.lines[index].time + 5.0
        let lineDuration = lineEnd - lineStart
        if lineDuration > 0 {
            progress = min(1.0, max(0.0, (adjustedPosition - lineStart) / lineDuration))
        }

        // Calculate per-word progress
        let timings = wordTimings(for: index, lineDuration: lineDuration)
        if currentWords.count != timings.count {
            currentWords = timings.map { $0.text }
        }
        var newProgresses = [Double](repeating: 0, count: timings.count)
        let posInLine = adjustedPosition - lineStart
        for (i, word) in timings.enumerated() {
            let wordStart = word.offset
            let wordEnd: Double
            if i + 1 < timings.count {
                wordEnd = timings[i + 1].offset
            } else {
                wordEnd = lineDuration
            }
            let wordDuration = wordEnd - wordStart
            if wordDuration > 0 {
                newProgresses[i] = min(1.0, max(0.0, (posInLine - wordStart) / wordDuration))
            } else {
                newProgresses[i] = posInLine >= wordStart ? 1.0 : 0.0
            }
        }
        wordProgresses = newProgresses
    }

    private func wordTimings(for index: Int, lineDuration: Double) -> [WordTiming] {
        guard let lyrics = lyrics, index >= 0, index < lyrics.lines.count else { return [] }
        let line = lyrics.lines[index]
        if let words = line.words, !words.isEmpty {
            return words
        }
        if let cached = estimatedTimingsCache, cached.index == index {
            return cached.timings
        }
        let estimated = Self.estimateWordTimings(text: line.text, lineDuration: lineDuration)
        estimatedTimingsCache = (index: index, timings: estimated)
        return estimated
    }

    /// Estimate word timings by distributing duration proportional to character count.
    public nonisolated static func estimateWordTimings(text: String, lineDuration: Double) -> [WordTiming] {
        let wordTexts = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !wordTexts.isEmpty, lineDuration > 0 else { return [] }

        let totalChars = wordTexts.reduce(0) { $0 + $1.count }
        guard totalChars > 0 else { return [] }

        var offset = 0.0
        return wordTexts.map { word in
            let timing = WordTiming(text: word, offset: offset)
            offset += lineDuration * Double(word.count) / Double(totalChars)
            return timing
        }
    }
}
