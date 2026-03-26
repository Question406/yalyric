import AppKit
import Combine

@MainActor
class SpotifyBridge: ObservableObject {
    @Published var currentTrack: TrackInfo?
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: TimeInterval = 0

    private var pollTimer: Timer?
    private var lastTrackID: String?

    func startPolling(interval: TimeInterval = 0.5) {
        stopPolling()
        fetchCurrentState()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.fetchCurrentState()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func fetchCurrentState() {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    set trackID to id of current track
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set trackDuration to duration of current track
                    set playerPos to player position
                    return trackID & "||" & trackName & "||" & trackArtist & "||" & trackAlbum & "||" & (trackDuration as text) & "||" & (playerPos as text) & "||playing"
                else if player state is paused then
                    set trackID to id of current track
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set trackDuration to duration of current track
                    set playerPos to player position
                    return trackID & "||" & trackName & "||" & trackArtist & "||" & trackAlbum & "||" & (trackDuration as text) & "||" & (playerPos as text) & "||paused"
                else
                    return "stopped"
                end if
            end tell
        else
            return "not_running"
        end if
        """

        guard let appleScript = NSAppleScript(source: script) else { return }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if error != nil {
            currentTrack = nil
            isPlaying = false
            return
        }

        let output = result.stringValue ?? ""

        if output == "not_running" || output == "stopped" {
            currentTrack = nil
            isPlaying = false
            return
        }

        let parts = output.components(separatedBy: "||")
        guard parts.count >= 7 else { return }

        let trackID = parts[0]
        let name = parts[1]
        let artist = parts[2]
        let album = parts[3]
        let durationMs = Double(parts[4]) ?? 0
        let position = Double(parts[5]) ?? 0
        let state = parts[6]

        isPlaying = (state == "playing")
        playbackPosition = position

        let track = TrackInfo(
            id: trackID,
            name: name,
            artist: artist,
            album: album,
            duration: durationMs / 1000.0
        )
        currentTrack = track
    }
}
