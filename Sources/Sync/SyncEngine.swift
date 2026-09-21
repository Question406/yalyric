import Foundation
import Combine

@MainActor
public class SyncEngine: ObservableObject {
    @Published public var currentLineIndex: Int = -1
    @Published public var currentLine: String = ""
    @Published public var nextLine: String = ""
    /// What the overlay's second line should show: the upcoming lyric, or this
    /// line's translation / romaji. Resolved per line so one untranslated line
    /// in a translated song falls back instead of leaving a gap.
    @Published public var secondaryLine: String = ""
    @Published public var progress: Double = 0  // 0-1 within current line

    /// Assigned by `AppDelegate` from the saved setting rather than read from
    /// `AppConfig` here, so the 0.5s sync path stays free of defaults lookups
    /// and the resolution below stays unit testable.
    public var secondaryContent: SecondaryLine = .nextLine {
        didSet { refreshSecondaryLine() }
    }

    /// Manual offset in seconds. Positive = lyrics appear earlier, negative = later.
    public var offset: TimeInterval = 0

    private var lyrics: Lyrics?

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
        secondaryLine = ""
        progress = 0
    }

    /// Resolves the second line against the current mode. Anything the chosen
    /// mode cannot supply for this particular line falls back to the upcoming
    /// lyric, which is what the overlay showed before this setting existed.
    private func refreshSecondaryLine() {
        guard let lyrics, currentLineIndex >= 0, currentLineIndex < lyrics.lines.count else {
            secondaryLine = nextLine
            return
        }
        let line = lyrics.lines[currentLineIndex]
        switch secondaryContent {
        case .nextLine:    secondaryLine = nextLine
        case .translation: secondaryLine = line.translation ?? nextLine
        case .romaji:      secondaryLine = line.romaji ?? nextLine
        }
    }

    public func update(position: TimeInterval) {
        let adjustedPosition = position + offset

        guard let lyrics = lyrics, !lyrics.lines.isEmpty else {
            currentLineIndex = -1
            currentLine = ""
            nextLine = ""
            secondaryLine = ""
            progress = 0
            return
        }

        guard lyrics.isSynced else {
            // For unsynced lyrics, don't try to sync
            if currentLineIndex == -1 {
                currentLineIndex = 0
                currentLine = lyrics.lines.first?.text ?? ""
                nextLine = lyrics.lines.count > 1 ? lyrics.lines[1].text : ""
                refreshSecondaryLine()
            }
            return
        }

        guard let index = lyrics.currentLineIndex(at: adjustedPosition) else {
            // Before first lyric line
            currentLineIndex = -1
            currentLine = ""
            nextLine = lyrics.lines.first?.text ?? ""
            refreshSecondaryLine()
            progress = 0
            return
        }

        if index != currentLineIndex {
            currentLineIndex = index
            currentLine = lyrics.lines[index].text
            nextLine = (index + 1 < lyrics.lines.count) ? lyrics.lines[index + 1].text : ""
            refreshSecondaryLine()
        }

        // Calculate progress within current line
        let lineStart = lyrics.lines[index].time
        let lineEnd = (index + 1 < lyrics.lines.count) ? lyrics.lines[index + 1].time : lyrics.lines[index].time + 5.0
        let lineDuration = lineEnd - lineStart
        if lineDuration > 0 {
            progress = min(1.0, max(0.0, (adjustedPosition - lineStart) / lineDuration))
        }
    }
}
