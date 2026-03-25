import Foundation
import Combine

@MainActor
class SyncEngine: ObservableObject {
    @Published var currentLineIndex: Int = -1
    @Published var currentLine: String = ""
    @Published var nextLine: String = ""
    @Published var progress: Double = 0  // 0-1 within current line

    private var lyrics: Lyrics?

    var allLines: [LyricLine] {
        lyrics?.lines ?? []
    }

    var isSynced: Bool {
        lyrics?.isSynced ?? false
    }

    func setLyrics(_ lyrics: Lyrics?) {
        self.lyrics = lyrics
        currentLineIndex = -1
        currentLine = ""
        nextLine = ""
        progress = 0
    }

    func update(position: TimeInterval) {
        guard let lyrics = lyrics, !lyrics.lines.isEmpty else {
            currentLineIndex = -1
            currentLine = ""
            nextLine = ""
            progress = 0
            return
        }

        guard lyrics.isSynced else {
            // For unsynced lyrics, don't try to sync
            if currentLineIndex == -1 {
                currentLineIndex = 0
                currentLine = lyrics.lines.first?.text ?? ""
                nextLine = lyrics.lines.count > 1 ? lyrics.lines[1].text : ""
            }
            return
        }

        guard let index = lyrics.currentLineIndex(at: position) else {
            // Before first lyric line
            if currentLineIndex != -1 {
                currentLineIndex = -1
                currentLine = ""
                nextLine = lyrics.lines.first?.text ?? ""
                progress = 0
            }
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
            progress = min(1.0, max(0.0, (position - lineStart) / lineDuration))
        }
    }
}
