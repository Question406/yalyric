import AppKit

@MainActor
final class AppleMusicBridge: AppleScriptBridge, PlayerBridge {
    override var playerName: String { "Apple Music" }

    override nonisolated var compiledScript: NSAppleScript? { Self._compiledScript }

    private nonisolated(unsafe) static let _compiledScript: NSAppleScript? = {
        let source = """
        if application "Music" is running then
            tell application "Music"
                if player state is playing then
                    set trackID to database ID of current track
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set trackDuration to duration of current track
                    set playerPos to player position
                    return (trackID as text) & "||" & trackName & "||" & trackArtist & "||" & trackAlbum & "||" & (trackDuration as text) & "||" & (playerPos as text) & "||playing"
                else if player state is paused then
                    set trackID to database ID of current track
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set trackDuration to duration of current track
                    set playerPos to player position
                    return (trackID as text) & "||" & trackName & "||" & trackArtist & "||" & trackAlbum & "||" & (trackDuration as text) & "||" & (playerPos as text) & "||paused"
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

    override func parseResult(_ output: String) {
        let parts = output.components(separatedBy: "||")
        guard parts.count >= 7 else { return }

        let trackID = parts[0]
        let name = parts[1]
        let artist = parts[2]
        let album = parts[3]
        let duration = Double(parts[4]) ?? 0  // Apple Music returns seconds (not ms)
        let position = Double(parts[5]) ?? 0
        let state = parts[6]

        isPlaying = (state == "playing")
        playbackPosition = position

        guard duration > 0 else {
            currentTrack = nil
            return
        }
        nonMusicTitle = nil

        let track = TrackInfo(
            id: "applemusic:\(trackID)",
            name: name,
            artist: artist,
            album: album,
            duration: duration  // already in seconds
        )
        currentTrack = track
    }
}
