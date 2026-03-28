import AppKit
import Combine

/// Common interface for music player integrations.
/// Conformers poll a music player and publish track/playback state.
@MainActor
protocol PlayerBridge: ObservableObject {
    var currentTrack: TrackInfo? { get }
    var isPlaying: Bool { get }
    var playbackPosition: TimeInterval { get }
    var permissionDenied: Bool { get }
    var nonMusicTitle: String? { get }
    var playerName: String { get }

    func startPolling()
    func stopPolling()
}

/// Base class for AppleScript-based player bridges.
/// Handles polling, timeout, adaptive intervals. Subclasses provide the script and result parsing.
@MainActor
class AppleScriptBridge: ObservableObject {
    @Published var currentTrack: TrackInfo?
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: TimeInterval = 0
    @Published var permissionDenied: Bool = false
    @Published var nonMusicTitle: String?

    private var pollTimer: Timer?
    private let activeInterval: TimeInterval = 0.5
    private let idleInterval: TimeInterval = 2.0

    private static let pollQueue = DispatchQueue(label: "com.yalyric.poll", qos: .userInitiated)
    private static let scriptQueue = DispatchQueue(label: "com.yalyric.script", qos: .userInitiated)

    // Subclasses must override
    var playerName: String { "" }
    nonisolated var compiledScript: NSAppleScript? { nil }
    func parseResult(_ output: String) {}

    func startPolling() {
        stopPolling()
        poll()
        schedulePoll(interval: activeInterval)
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func schedulePoll(interval: TimeInterval) {
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.poll()
                let next = self.isPlaying ? self.activeInterval : self.idleInterval
                self.schedulePoll(interval: next)
            }
        }
    }

    private func poll() {
        let script = compiledScript
        Self.pollQueue.async { [weak self] in
            var output = "error"
            let semaphore = DispatchSemaphore(value: 0)

            Self.scriptQueue.async {
                guard let script else {
                    semaphore.signal()
                    return
                }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                if let error = error {
                    let errorNum = error[NSAppleScript.errorNumber] as? Int
                    output = errorNum == -1743 ? "permission_denied" : "error"
                } else {
                    output = result.stringValue ?? ""
                }
                semaphore.signal()
            }

            let result = semaphore.wait(timeout: .now() + 3.0)
            let finalOutput = result == .timedOut ? "error" : output

            DispatchQueue.main.async {
                self?.handleOutput(finalOutput)
            }
        }
    }

    private func handleOutput(_ output: String) {
        if output == "permission_denied" {
            permissionDenied = true
            currentTrack = nil
            isPlaying = false
            return
        }
        permissionDenied = false

        if output == "not_running" || output == "stopped" || output == "error" || output.isEmpty {
            currentTrack = nil
            isPlaying = false
            return
        }

        parseResult(output)
    }
}
