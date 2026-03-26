import AppKit
import Combine

@MainActor
class SpotifyBridge: ObservableObject {
    @Published var currentTrack: TrackInfo?
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: TimeInterval = 0
    @Published var permissionDenied: Bool = false

    private var pollTimer: Timer?
    private let activeInterval: TimeInterval = 0.5
    private let idleInterval: TimeInterval = 2.0

    /// Pre-compiled script — compiled once, reused every poll
    private nonisolated(unsafe) static let compiledScript: NSAppleScript? = {
        let source = """
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
        let script = NSAppleScript(source: source)
        script?.compileAndReturnError(nil)
        return script
    }()

    private static let pollQueue = DispatchQueue(label: "com.yalyric.spotify-poll", qos: .userInitiated)

    func startPolling() {
        stopPolling()
        poll()
        schedulePoll(interval: activeInterval)
    }

    private func schedulePoll(interval: TimeInterval) {
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.poll()
                // Poll fast while playing, slow down when idle
                let next = self.isPlaying ? self.activeInterval : self.idleInterval
                self.schedulePoll(interval: next)
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func poll() {
        // Run AppleScript on a background queue to avoid blocking the main thread
        Self.pollQueue.async { [weak self] in
            let output = Self.executeScript()
            DispatchQueue.main.async {
                self?.handleResult(output)
            }
        }
    }

    private nonisolated static func executeScript() -> String {
        guard let script = compiledScript else { return "error" }

        // NSAppleScript is not thread-safe — but we only call from our serial queue
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            // Error -1743 = "Not authorized to send Apple events"
            let errorNum = error[NSAppleScript.errorNumber] as? Int
            if errorNum == -1743 {
                return "permission_denied"
            }
            return "error"
        }
        return result.stringValue ?? ""
    }

    private func handleResult(_ output: String) {
        if output == "permission_denied" {
            permissionDenied = true
            currentTrack = nil
            isPlaying = false
            return
        }
        permissionDenied = false

        if output == "not_running" || output == "stopped" || output == "error" {
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
