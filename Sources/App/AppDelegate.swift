import AppKit
import Combine

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let spotifyBridge = SpotifyBridge()
    private let lyricsManager = LyricsManager()
    private let syncEngine = SyncEngine()

    private var overlayWindow: OverlayWindow?
    private var desktopWidget: DesktopWidget?
    private var menuBarController: MenuBarController?

    private var settingsWindowController: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var lastDisplayedLineIndex: Int = -2  // -2 = never displayed
    private var lastDisplayState: DisplayState = .noTrack
    private var autoHideTimer: Timer?
    private var isOverlayHidden = false
    private var hasShownOnboarding = false
    private var hasEverPlayed = false

    private enum DisplayState: Equatable {
        case noTrack, nonMusic, permissionDenied, loading, noLyrics, intro, lyrics
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar app
        NSApp.setActivationPolicy(.accessory)

        setupDisplayModes()
        setupBindings()
        showOnboardingIfNeeded()
        syncEngine.offset = SettingsManager.shared.lyricsOffset
        spotifyBridge.startPolling()

        NotificationCenter.default.addObserver(
            self, selector: #selector(displayModesDidChange),
            name: .displayModesChanged, object: nil
        )
    }

    private func setupDisplayModes() {
        let settings = SettingsManager.shared
        let modes = settings.enabledDisplayModes

        // Always create menu bar (needed for settings access)
        if menuBarController == nil {
            menuBarController = MenuBarController()
            setupMenuBarMenu()
        }

        if modes.contains(.overlay) {
            if overlayWindow == nil { overlayWindow = OverlayWindow() }
            overlayWindow?.orderFront(nil)
        } else {
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
        }

        if modes.contains(.desktop) {
            if desktopWidget == nil { desktopWidget = DesktopWidget() }
            desktopWidget?.orderFront(nil)
        } else {
            desktopWidget?.orderOut(nil)
            desktopWidget = nil
        }


    }

    private func setupMenuBarMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let moveItem = NSMenuItem(title: "Move Overlay...", action: #selector(toggleOverlayEditMode), keyEquivalent: "m")
        moveItem.target = self
        menu.addItem(moveItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit yalyric", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        menuBarController?.contextMenu = menu
    }

    @objc private func toggleOverlayEditMode() {
        overlayWindow?.toggleEditMode()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        if let moveItem = menu.items.first(where: { $0.action == #selector(toggleOverlayEditMode) }) {
            let editing = overlayWindow?.isEditMode ?? false
            moveItem.title = editing ? "Lock Overlay Position" : "Move Overlay..."
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func displayModesDidChange() {
        setupDisplayModes()
    }

    private func setupBindings() {
        // When track changes, fetch lyrics
        spotifyBridge.$currentTrack
            .removeDuplicates()
            .sink { [weak self] track in
                guard let self, let track else {
                    self?.lastDisplayedLineIndex = -2
                    self?.lastDisplayState = .noTrack
                    self?.syncEngine.setLyrics(nil)
                    self?.updateAllDisplays()
                    return
                }
                self.lastDisplayedLineIndex = -2
                self.lastDisplayState = .noTrack
                self.hasShownOnboarding = false
                self.lyricsManager.fetchLyrics(for: track)
            }
            .store(in: &cancellables)

        // When lyrics are fetched, update sync engine
        lyricsManager.$currentLyrics
            .sink { [weak self] lyrics in
                self?.lastDisplayedLineIndex = -2
                self?.syncEngine.setLyrics(lyrics)
            }
            .store(in: &cancellables)

        // When playback position changes, update sync
        spotifyBridge.$playbackPosition
            .sink { [weak self] position in
                guard let self else { return }
                self.syncEngine.update(position: position)
                self.updateAllDisplays()
            }
            .store(in: &cancellables)

        // Sync offset from settings
        SettingsManager.shared.$lyricsOffset
            .sink { [weak self] offset in
                self?.syncEngine.offset = offset
                self?.lastDisplayedLineIndex = -2  // force redraw
            }
            .store(in: &cancellables)

        // React to playing state — auto-hide overlay when paused
        spotifyBridge.$isPlaying
            .dropFirst()  // skip initial false at launch
            .removeDuplicates()
            .sink { [weak self] playing in
                guard let self else { return }
                if playing {
                    self.hasEverPlayed = true
                    self.cancelAutoHide()
                    self.showOverlay()
                } else if self.hasEverPlayed {
                    // Only auto-hide if we've confirmed playback before
                    // (avoids hiding on transient AppleScript errors)
                    self.menuBarController?.updateCurrentLine("")
                    self.scheduleAutoHide()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Onboarding

    private func showOnboardingIfNeeded() {
        let key = "hasLaunchedBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        hasShownOnboarding = true
        overlayWindow?.showTrackInfo(
            title: "yalyric is running",
            artist: "Play a song in Spotify to see lyrics"
        )
    }

    // MARK: - Auto-hide

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        let settings = SettingsManager.shared
        guard settings.autoHideOnPause else { return }

        let delay = settings.autoHideDelay
        if delay <= 0 {
            hideOverlay()
            return
        }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hideOverlay()
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    private func hideOverlay() {
        guard !isOverlayHidden else { return }
        isOverlayHidden = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.overlayWindow?.animator().alphaValue = 0
        }
    }

    private func showOverlay() {
        guard isOverlayHidden else { return }
        isOverlayHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.overlayWindow?.animator().alphaValue = 1
        }
    }

    private func updateAllDisplays() {
        let currentLine = syncEngine.currentLine
        let nextLine = syncEngine.nextLine
        let index = syncEngine.currentLineIndex
        let lines = syncEngine.allLines
        let track = spotifyBridge.currentTrack

        // Determine current display state
        let state: DisplayState
        if spotifyBridge.permissionDenied {
            state = .permissionDenied
        } else if track == nil && spotifyBridge.nonMusicTitle != nil {
            state = .nonMusic
        } else if track == nil {
            state = .noTrack
        } else if lyricsManager.isFetching {
            state = .loading
        } else if lyricsManager.errorMessage != nil {
            state = .noLyrics
        } else if index == -1 && spotifyBridge.isPlaying {
            state = .intro
        } else {
            state = .lyrics
        }

        // Skip if nothing changed — but always update progress for karaoke fill
        let karaokeFillActive = ThemeManager.shared.theme.karaokeFillEnabled
        if state == .lyrics && state == lastDisplayState && index == lastDisplayedLineIndex && !karaokeFillActive {
            return
        }
        lastDisplayState = state
        lastDisplayedLineIndex = index

        if spotifyBridge.permissionDenied {
            overlayWindow?.updateSource(nil)
            overlayWindow?.showTrackInfo(
                title: "Automation permission needed",
                artist: "System Settings → Privacy → Automation → enable Spotify for yalyric"
            )
            menuBarController?.updateCurrentLine("Permission needed")
            return
        }

        if let nonMusicTitle = spotifyBridge.nonMusicTitle, track == nil {
            // Podcast, DJ interlude, or ad — hide overlay, show title in menu bar
            overlayWindow?.updateSource(nil)
            overlayWindow?.updateLyrics(current: "", next: "")
            menuBarController?.updateCurrentLine("🎙 \(nonMusicTitle)")
            return
        }

        if track == nil {
            // No track playing
            overlayWindow?.updateSource(nil)
            overlayWindow?.updateLyrics(current: "", next: "")
            menuBarController?.updateCurrentLine("")
            return
        }

        if lyricsManager.isFetching {
            // Still loading lyrics — show track info
            overlayWindow?.updateSource(nil)
            overlayWindow?.showTrackInfo(
                title: track!.name,
                artist: track!.artist
            )
            menuBarController?.updateCurrentLine(track!.name)
            return
        }

        if lyricsManager.errorMessage != nil {
            // No lyrics found — show track info with hint
            overlayWindow?.showTrackInfo(
                title: track!.name,
                artist: "\(track!.artist) · No lyrics available"
            )
            menuBarController?.updateCurrentLine(track!.name)
            return
        }

        if index == -1 && spotifyBridge.isPlaying {
            // Before first lyric line (intro) — show track info
            let firstLine = lines.first?.text ?? ""
            overlayWindow?.showTrackInfo(
                title: track!.name,
                artist: firstLine.isEmpty ? track!.artist : "♪ \(track!.artist)"
            )
            menuBarController?.updateCurrentLine(track!.name)
            menuBarController?.updateLyrics(lines: lines, currentIndex: index)
            desktopWidget?.updateLyrics(lines: lines, currentIndex: index)
            return
        }

        // Normal lyrics display
        let isSynced = lyricsManager.currentLyrics?.isSynced ?? false
        overlayWindow?.updateSource(lyricsManager.currentLyrics?.source, isSynced: isSynced)
        menuBarController?.updateSource(lyricsManager.currentLyrics?.source, isSynced: isSynced)
        overlayWindow?.updateLyrics(current: currentLine, next: nextLine)
        overlayWindow?.updateProgress(syncEngine.progress)
        menuBarController?.updateProgress(syncEngine.progress)
        desktopWidget?.updateLyrics(lines: lines, currentIndex: index)

        if spotifyBridge.isPlaying {
            menuBarController?.updateCurrentLine(currentLine, isSynced: isSynced)
        }
        menuBarController?.updateLyrics(lines: lines, currentIndex: index)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        spotifyBridge.stopPolling()
    }
}
