import Foundation
import Combine

@MainActor
public class LyricsManager: ObservableObject {
    @Published var currentLyrics: Lyrics?
    @Published var isFetching: Bool = false
    @Published var errorMessage: String?

    private let allProviders: [String: LyricsProvider] = [
        "lrclib": LRCLIBProvider(),
        "spotify": SpotifyInternalProvider(),
        "musixmatch": MusixmatchProvider(),
        "netease": NetEaseProvider()
    ]

    private var orderedProviders: [LyricsProvider] {
        let order = UserDefaults.standard.stringArray(forKey: "providerOrder")
            ?? ["lrclib", "spotify", "musixmatch", "netease"]
        return order.compactMap { allProviders[$0] }
    }
    private var cache: [String: Lyrics] = [:]
    private var currentFetchTask: Task<Void, Never>?
    private var currentTrackID: String?

    func fetchLyrics(for track: TrackInfo) {
        let trackID = track.id
        currentTrackID = trackID

        // Check cache
        if let cached = cache[trackID] {
            currentLyrics = cached
            errorMessage = nil
            return
        }

        // Cancel previous fetch
        currentFetchTask?.cancel()
        isFetching = true
        errorMessage = nil

        let langPref = UserDefaults.standard.string(forKey: "lyricsLanguage")
            .flatMap { LyricsLanguagePreference(rawValue: $0) } ?? .auto

        currentFetchTask = Task {
            var bestLyrics: Lyrics?
            var fallbackLyrics: Lyrics?  // wrong language but still usable

            for provider in orderedProviders {
                if Task.isCancelled { return }
                do {
                    if let lyrics = try await provider.fetch(track: track) {
                        let langMatch = LyricsLanguageDetector.matches(
                            lyrics: lyrics,
                            preference: langPref,
                            trackName: track.name,
                            trackArtist: track.artist
                        )

                        if lyrics.isSynced && langMatch {
                            bestLyrics = lyrics
                            break
                        } else if lyrics.isSynced && fallbackLyrics == nil {
                            // Wrong language but synced — keep as fallback
                            fallbackLyrics = lyrics
                        } else if bestLyrics == nil && langMatch {
                            bestLyrics = lyrics
                        } else if fallbackLyrics == nil {
                            fallbackLyrics = lyrics
                        }
                    }
                } catch {
                    print("[\(provider.source.rawValue)] Error: \(error.localizedDescription)")
                }
            }

            if Task.isCancelled { return }
            guard currentTrackID == trackID else { return }

            // Prefer language-matched lyrics, fall back to any lyrics
            let result = bestLyrics ?? fallbackLyrics

            if let lyrics = result {
                cache[trackID] = lyrics
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
