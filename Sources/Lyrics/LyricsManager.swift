import Foundation
import Combine

@MainActor
public class LyricsManager: ObservableObject {
    @Published var currentLyrics: Lyrics?
    @Published var isFetching: Bool = false
    @Published var errorMessage: String?

    private var providers: [LyricsProvider] = [
        LRCLIBProvider(),
        SpotifyInternalProvider(),
        MusixmatchProvider(),
        NetEaseProvider()
    ]
    private var cache: [String: Lyrics] = [:]
    private var currentFetchTask: Task<Void, Never>?

    func addProvider(_ provider: LyricsProvider) {
        providers.append(provider)
    }

    func fetchLyrics(for track: TrackInfo) {
        // Check cache
        if let cached = cache[track.id] {
            currentLyrics = cached
            errorMessage = nil
            return
        }

        // Cancel previous fetch
        currentFetchTask?.cancel()
        isFetching = true
        errorMessage = nil

        currentFetchTask = Task {
            var bestLyrics: Lyrics?

            for provider in providers {
                if Task.isCancelled { return }
                do {
                    if let lyrics = try await provider.fetch(track: track) {
                        if lyrics.isSynced {
                            // Synced lyrics found — use immediately
                            bestLyrics = lyrics
                            break
                        } else if bestLyrics == nil {
                            // Keep plain lyrics as fallback
                            bestLyrics = lyrics
                        }
                    }
                } catch {
                    print("[\(provider.source.rawValue)] Error: \(error.localizedDescription)")
                }
            }

            if Task.isCancelled { return }

            if let lyrics = bestLyrics {
                cache[track.id] = lyrics
                currentLyrics = lyrics
                errorMessage = nil
            } else {
                currentLyrics = nil
                errorMessage = "No lyrics found"
            }
            isFetching = false
        }
    }

    func clearCache() {
        cache.removeAll()
    }
}
