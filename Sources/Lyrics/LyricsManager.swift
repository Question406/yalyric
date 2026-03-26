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

    // MARK: - LRU Memory Cache

    private var memoryCache: [String: Lyrics] = [:]
    private var accessOrder: [String] = []  // most-recently-used at end
    private let maxMemoryCacheSize = 50

    private func memoryCacheGet(_ key: String) -> Lyrics? {
        guard let lyrics = memoryCache[key] else { return nil }
        // Move to end (most recent)
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(key)
        return lyrics
    }

    private func memoryCacheSet(_ key: String, _ lyrics: Lyrics) {
        if memoryCache[key] != nil {
            if let idx = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: idx)
            }
        } else if memoryCache.count >= maxMemoryCacheSize {
            // Evict oldest
            let oldest = accessOrder.removeFirst()
            memoryCache.removeValue(forKey: oldest)
        }
        memoryCache[key] = lyrics
        accessOrder.append(key)
    }

    // MARK: - Disk Cache

    private static let diskCacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("yalyric/lyrics", isDirectory: true)
    }()
    private static let maxDiskCacheSize = 200

    private func diskCachePath(for trackID: String) -> URL {
        let safe = trackID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? trackID
        return Self.diskCacheDir.appendingPathComponent("\(safe).json")
    }

    private func loadFromDisk(_ trackID: String) -> Lyrics? {
        let path = diskCachePath(for: trackID)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(Lyrics.self, from: data)
    }

    private func saveToDisk(_ trackID: String, _ lyrics: Lyrics) {
        let fm = FileManager.default
        let dir = Self.diskCacheDir
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        guard let data = try? JSONEncoder().encode(lyrics) else { return }
        try? data.write(to: diskCachePath(for: trackID), options: .atomic)

        // Evict oldest files if over limit
        evictDiskCacheIfNeeded()
    }

    private func evictDiskCacheIfNeeded() {
        let fm = FileManager.default
        let dir = Self.diskCacheDir
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        guard files.count > Self.maxDiskCacheSize else { return }

        // Sort by modification date, oldest first
        let sorted = files.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            return (url, date)
        }.sorted { $0.1 < $1.1 }

        let toRemove = sorted.prefix(files.count - Self.maxDiskCacheSize)
        for (url, _) in toRemove {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Scoring

    private static let maxScore = 5

    static func scoreLyrics(
        _ lyrics: Lyrics,
        langPref: LyricsLanguagePreference,
        trackName: String,
        trackArtist: String
    ) -> Int {
        var score = 0
        if lyrics.isSynced { score += 3 }
        if LyricsLanguageDetector.matches(
            lyrics: lyrics, preference: langPref,
            trackName: trackName, trackArtist: trackArtist
        ) { score += 1 }
        if lyrics.lines.count > 5 { score += 1 }
        return score
    }

    // MARK: - Fetch (parallel)

    private var currentFetchTask: Task<Void, Never>?
    private var currentTrackID: String?

    func fetchLyrics(for track: TrackInfo) {
        let trackID = track.id
        currentTrackID = trackID

        // Check memory cache
        if let cached = memoryCacheGet(trackID) {
            currentLyrics = cached
            errorMessage = nil
            return
        }

        // Check disk cache
        if let cached = loadFromDisk(trackID) {
            memoryCacheSet(trackID, cached)
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
        let providers = orderedProviders

        currentFetchTask = Task {
            // Query all providers concurrently
            let results: [(index: Int, lyrics: Lyrics)] = await withTaskGroup(
                of: (Int, Lyrics?).self
            ) { group in
                for (index, provider) in providers.enumerated() {
                    group.addTask {
                        do {
                            let lyrics = try await provider.fetch(track: track)
                            return (index, lyrics)
                        } catch {
                            print("[\(provider.source.rawValue)] Error: \(error.localizedDescription)")
                            return (index, nil)
                        }
                    }
                }

                var collected: [(index: Int, lyrics: Lyrics)] = []
                for await (index, lyrics) in group {
                    guard let lyrics else { continue }
                    collected.append((index, lyrics))

                    // Early return on perfect match — no need to wait for slower providers
                    let score = Self.scoreLyrics(lyrics, langPref: langPref, trackName: track.name, trackArtist: track.artist)
                    if score >= Self.maxScore {
                        group.cancelAll()
                        break
                    }
                }
                return collected
            }

            if Task.isCancelled { return }
            guard currentTrackID == trackID else { return }

            // Pick the best result: highest score, then provider order as tiebreaker
            let best = results
                .sorted { lhs, rhs in
                    let lScore = Self.scoreLyrics(lhs.lyrics, langPref: langPref, trackName: track.name, trackArtist: track.artist)
                    let rScore = Self.scoreLyrics(rhs.lyrics, langPref: langPref, trackName: track.name, trackArtist: track.artist)
                    if lScore != rScore { return lScore > rScore }
                    return lhs.index < rhs.index
                }
                .first?.lyrics

            if let lyrics = best {
                memoryCacheSet(trackID, lyrics)
                saveToDisk(trackID, lyrics)
                currentLyrics = lyrics
                errorMessage = nil
                print("[yalyric] Selected \(lyrics.source.rawValue) (synced: \(lyrics.isSynced), lines: \(lyrics.lines.count))")
            } else {
                currentLyrics = nil
                errorMessage = "No lyrics found"
            }
            isFetching = false
        }
    }

    func clearCache() {
        memoryCache.removeAll()
        accessOrder.removeAll()
        // Also clear disk cache
        try? FileManager.default.removeItem(at: Self.diskCacheDir)
    }
}
