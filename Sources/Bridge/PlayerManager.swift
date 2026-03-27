import AppKit
import Combine

/// Manages multiple player bridges. Auto-detects which player is active
/// and forwards its state as a unified stream.
@MainActor
class PlayerManager: ObservableObject {
    @Published var currentTrack: TrackInfo?
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: TimeInterval = 0
    @Published var permissionDenied: Bool = false
    @Published var nonMusicTitle: String?
    @Published var activePlayerName: String = ""

    private let spotifyBridge = SpotifyBridge()
    private let appleMusicBridge = AppleMusicBridge()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Forward Spotify state
        spotifyBridge.$currentTrack.sink { [weak self] _ in self?.resolve() }.store(in: &cancellables)
        spotifyBridge.$isPlaying.sink { [weak self] _ in self?.resolve() }.store(in: &cancellables)
        spotifyBridge.$playbackPosition.sink { [weak self] _ in self?.resolve() }.store(in: &cancellables)
        spotifyBridge.$permissionDenied.sink { [weak self] _ in self?.resolve() }.store(in: &cancellables)
        spotifyBridge.$nonMusicTitle.sink { [weak self] _ in self?.resolve() }.store(in: &cancellables)

        // Forward Apple Music state
        appleMusicBridge.$currentTrack.sink { [weak self] _ in self?.resolve() }.store(in: &cancellables)
        appleMusicBridge.$isPlaying.sink { [weak self] _ in self?.resolve() }.store(in: &cancellables)
        appleMusicBridge.$playbackPosition.sink { [weak self] _ in self?.resolve() }.store(in: &cancellables)
        appleMusicBridge.$permissionDenied.sink { [weak self] _ in self?.resolve() }.store(in: &cancellables)
        appleMusicBridge.$nonMusicTitle.sink { [weak self] _ in self?.resolve() }.store(in: &cancellables)
    }

    func startPolling() {
        spotifyBridge.startPolling()
        appleMusicBridge.startPolling()
    }

    func stopPolling() {
        spotifyBridge.stopPolling()
        appleMusicBridge.stopPolling()
    }

    /// Pick the active player: prefer whichever is currently playing.
    /// If both are playing, prefer Spotify (more common use case).
    /// If neither is playing, show the one that has a track (paused).
    private func resolve() {
        let spotify = spotifyBridge
        let music = appleMusicBridge

        if spotify.isPlaying {
            forward(spotify)
        } else if music.isPlaying {
            forward(music)
        } else if spotify.currentTrack != nil {
            forward(spotify)
        } else if music.currentTrack != nil {
            forward(music)
        } else {
            // Neither running
            activePlayerName = ""
            currentTrack = nil
            isPlaying = false
            playbackPosition = 0
            permissionDenied = spotify.permissionDenied || music.permissionDenied
            nonMusicTitle = spotify.nonMusicTitle ?? music.nonMusicTitle
        }
    }

    private func forward(_ bridge: AppleScriptBridge) {
        activePlayerName = bridge.playerName
        currentTrack = bridge.currentTrack
        isPlaying = bridge.isPlaying
        playbackPosition = bridge.playbackPosition
        permissionDenied = bridge.permissionDenied
        nonMusicTitle = bridge.nonMusicTitle
    }
}
