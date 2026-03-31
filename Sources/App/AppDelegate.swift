import AppKit
import Combine

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let playerManager = PlayerManager()
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
    private var allDisplaysHidden = false
    private var additionalOverlays: [OverlayWindow] = []
    private var additionalWidgets: [DesktopWidget] = []

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
        playerManager.startPolling()

        let hk = HotkeyManager.shared
        hk.onToggleOverlay = { [weak self] in self?.toggleOverlayVisibility() }
        hk.onToggleAll = { [weak self] in self?.toggleAllDisplays() }
        hk.onOffsetPlus = { [weak self] in self?.nudgeOffset(0.5) }
        hk.onOffsetMinus = { [weak self] in self?.nudgeOffset(-0.5) }
        hk.onOffsetReset = { [weak self] in self?.resetOffset() }
        hk.registerAll()

        NotificationCenter.default.addObserver(
            self, selector: #selector(displayModesDidChange),
            name: .displayModesChanged, object: nil
        )

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
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
            for w in additionalOverlays { w.orderOut(nil) }
            additionalOverlays.removeAll()
        }

        if modes.contains(.desktop) {
            if desktopWidget == nil { desktopWidget = DesktopWidget() }
            desktopWidget?.updateLineCount(settings.widgetLineCount)
            desktopWidget?.orderFront(nil)
        } else {
            desktopWidget?.orderOut(nil)
            desktopWidget = nil
            for w in additionalWidgets { w.orderOut(nil) }
            additionalWidgets.removeAll()
        }


    }

    private func setupMenuBarMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let moveOverlay = NSMenuItem(title: "Move Overlay...", action: #selector(toggleOverlayEditMode), keyEquivalent: "m")
        moveOverlay.target = self
        menu.addItem(moveOverlay)

        let moveWidget = NSMenuItem(title: "Move Widget...", action: #selector(toggleWidgetEditMode), keyEquivalent: "")
        moveWidget.target = self
        menu.addItem(moveWidget)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit yalyric", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        menuBarController?.contextMenu = menu
    }

    @objc private func toggleOverlayEditMode() {
        let behavior = DisplayBehavior(rawValue: AppConfig.get(AppConfig.Overlay.displayBehavior)) ?? .followMouse
        if behavior == .showOnAll {
            let mouse = NSEvent.mouseLocation
            let allOverlays = [overlayWindow].compactMap { $0 } + additionalOverlays
            if let target = allOverlays.first(where: { $0.screen?.frame.contains(mouse) == true }) {
                target.toggleEditMode()
            }
        } else {
            overlayWindow?.toggleEditMode()
        }
    }

    @objc private func toggleWidgetEditMode() {
        let behavior = DisplayBehavior(rawValue: AppConfig.get(AppConfig.Widget.displayBehavior)) ?? .followMouse
        if behavior == .showOnAll {
            let mouse = NSEvent.mouseLocation
            let allWidgets = [desktopWidget].compactMap { $0 } + additionalWidgets
            if let target = allWidgets.first(where: { $0.screen?.frame.contains(mouse) == true }) {
                target.toggleEditMode()
            }
        } else {
            desktopWidget?.toggleEditMode()
        }
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        if let item = menu.items.first(where: { $0.action == #selector(toggleOverlayEditMode) }) {
            let editing = overlayWindow?.isEditMode ?? false
            item.title = editing ? "Lock Overlay Position" : "Move Overlay..."
            item.isHidden = overlayWindow == nil
        }
        if let item = menu.items.first(where: { $0.action == #selector(toggleWidgetEditMode) }) {
            let editing = desktopWidget?.isEditMode ?? false
            item.title = editing ? "Lock Widget Position" : "Move Widget..."
            item.isHidden = desktopWidget == nil
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

    @objc private func screenParametersDidChange() {
        let screens = NSScreen.screens
        let overlayPinned = AppConfig.get(AppConfig.Overlay.pinnedScreenIndex)
        if overlayPinned >= screens.count {
            AppConfig.set(AppConfig.Overlay.pinnedScreenIndex, 0)
        }
        let widgetPinned = AppConfig.get(AppConfig.Widget.pinnedScreenIndex)
        if widgetPinned >= screens.count {
            AppConfig.set(AppConfig.Widget.pinnedScreenIndex, 0)
        }
        reconcileShowOnAll()
        lastDisplayedLineIndex = -2
    }

    private func reconcileShowOnAll() {
        let screens = NSScreen.screens

        // Overlay
        let overlayBehavior = DisplayBehavior(rawValue: AppConfig.get(AppConfig.Overlay.displayBehavior)) ?? .followMouse
        if overlayBehavior == .showOnAll && overlayWindow != nil {
            let needed = screens.count - 1
            while additionalOverlays.count < needed {
                let w = OverlayWindow()
                w.orderFront(nil)
                additionalOverlays.append(w)
            }
            while additionalOverlays.count > needed {
                let w = additionalOverlays.removeLast()
                w.orderOut(nil)
            }
            if let primary = screens.first {
                overlayWindow?.moveToScreen(primary, animated: false)
            }
            for (i, overlay) in additionalOverlays.enumerated() {
                let screenIndex = i + 1
                if screenIndex < screens.count {
                    overlay.moveToScreen(screens[screenIndex], animated: false)
                }
            }
        } else {
            for w in additionalOverlays { w.orderOut(nil) }
            additionalOverlays.removeAll()
        }

        // Widget
        let widgetBehavior = DisplayBehavior(rawValue: AppConfig.get(AppConfig.Widget.displayBehavior)) ?? .followMouse
        if widgetBehavior == .showOnAll && desktopWidget != nil {
            let needed = screens.count - 1
            while additionalWidgets.count < needed {
                let w = DesktopWidget()
                w.orderFront(nil)
                additionalWidgets.append(w)
            }
            while additionalWidgets.count > needed {
                let w = additionalWidgets.removeLast()
                w.orderOut(nil)
            }
            if let primary = screens.first {
                desktopWidget?.moveToScreen(primary, animated: false)
            }
            for (i, widget) in additionalWidgets.enumerated() {
                let screenIndex = i + 1
                if screenIndex < screens.count {
                    widget.moveToScreen(screens[screenIndex], animated: false)
                }
            }
        } else {
            for w in additionalWidgets { w.orderOut(nil) }
            additionalWidgets.removeAll()
        }
    }

    private func updateScreenTargets() {
        if let overlay = overlayWindow, !overlay.isEditMode {
            let behavior = DisplayBehavior(rawValue: AppConfig.get(AppConfig.Overlay.displayBehavior)) ?? .followMouse
            if behavior == .showOnAll {
                reconcileShowOnAll()
            } else {
                let target = ScreenDetector.targetScreen(behavior: behavior, pinnedIndex: AppConfig.get(AppConfig.Overlay.pinnedScreenIndex))
                overlay.moveToScreen(target)
            }
        }

        if let widget = desktopWidget, !widget.isEditMode {
            let behavior = DisplayBehavior(rawValue: AppConfig.get(AppConfig.Widget.displayBehavior)) ?? .followMouse
            if behavior == .showOnAll {
                reconcileShowOnAll()
            } else {
                let target = ScreenDetector.targetScreen(behavior: behavior, pinnedIndex: AppConfig.get(AppConfig.Widget.pinnedScreenIndex))
                widget.moveToScreen(target)
            }
        }
    }

    private func forEachOverlay(_ action: (OverlayWindow) -> Void) {
        if let primary = overlayWindow { action(primary) }
        for overlay in additionalOverlays { action(overlay) }
    }

    private func forEachWidget(_ action: (DesktopWidget) -> Void) {
        if let primary = desktopWidget { action(primary) }
        for widget in additionalWidgets { action(widget) }
    }

    private func setupBindings() {
        // When track changes, fetch lyrics
        playerManager.$currentTrack
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
        playerManager.$playbackPosition
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
        playerManager.$isPlaying
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
        guard !AppConfig.get(AppConfig.General.hasLaunchedBefore) else { return }
        AppConfig.set(AppConfig.General.hasLaunchedBefore, true)
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
            DispatchQueue.main.async {
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
        guard overlayWindow?.isEditMode != true else { return }
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
        guard !allDisplaysHidden else { return }
        updateScreenTargets()
        let currentLine = syncEngine.currentLine
        let nextLine = syncEngine.nextLine
        let index = syncEngine.currentLineIndex
        let lines = syncEngine.allLines
        let track = playerManager.currentTrack

        // Determine current display state
        let state: DisplayState
        if playerManager.permissionDenied {
            state = .permissionDenied
        } else if track == nil && playerManager.nonMusicTitle != nil {
            state = .nonMusic
        } else if track == nil {
            state = .noTrack
        } else if lyricsManager.isFetching {
            state = .loading
        } else if lyricsManager.errorMessage != nil {
            state = .noLyrics
        } else if index == -1 && playerManager.isPlaying {
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

        if playerManager.permissionDenied {
            forEachOverlay { $0.updateSource(nil) }
            forEachOverlay { $0.showTrackInfo(
                title: "Automation permission needed",
                artist: "System Settings → Privacy → Automation → enable Spotify for yalyric"
            ) }
            menuBarController?.updateCurrentLine("Permission needed")
            return
        }

        if let nonMusicTitle = playerManager.nonMusicTitle, track == nil {
            // Podcast, DJ interlude, or ad — hide overlay, show title in menu bar
            forEachOverlay { $0.updateSource(nil) }
            forEachOverlay { $0.updateLyrics(current: "", next: "") }
            menuBarController?.updateCurrentLine("🎙 \(nonMusicTitle)")
            return
        }

        if track == nil {
            // No track playing
            forEachOverlay { $0.updateSource(nil) }
            forEachOverlay { $0.updateLyrics(current: "", next: "") }
            menuBarController?.updateCurrentLine("")
            return
        }

        if lyricsManager.isFetching {
            // Still loading lyrics — show track info
            forEachOverlay { $0.updateSource(nil) }
            forEachOverlay { $0.showTrackInfo(
                title: track!.name,
                artist: track!.artist
            ) }
            menuBarController?.updateCurrentLine(track!.name)
            return
        }

        if lyricsManager.errorMessage != nil {
            // No lyrics found — show track info with hint
            forEachOverlay { $0.showTrackInfo(
                title: track!.name,
                artist: "\(track!.artist) · No lyrics available"
            ) }
            menuBarController?.updateCurrentLine(track!.name)
            return
        }

        if index == -1 && playerManager.isPlaying {
            // Before first lyric line (intro) — show track info
            let firstLine = lines.first?.text ?? ""
            forEachOverlay { $0.showTrackInfo(
                title: track!.name,
                artist: firstLine.isEmpty ? track!.artist : "♪ \(track!.artist)"
            ) }
            menuBarController?.updateCurrentLine(track!.name)
            menuBarController?.updateLyrics(lines: lines, currentIndex: index)
            forEachWidget { $0.updateLyrics(lines: lines, currentIndex: index, words: syncEngine.currentWords) }
            return
        }

        // Normal lyrics display
        let isSynced = lyricsManager.currentLyrics?.isSynced ?? false
        forEachOverlay { $0.updateSource(lyricsManager.currentLyrics?.source, isSynced: isSynced) }
        menuBarController?.updateSource(lyricsManager.currentLyrics?.source, isSynced: isSynced)
        let currentWords = syncEngine.currentWords
        forEachOverlay { $0.updateLyrics(current: currentLine, next: nextLine, words: currentWords) }
        let wordProgresses = syncEngine.wordProgresses
        forEachOverlay { $0.updateWordProgresses(wordProgresses) }
        forEachOverlay { $0.updateProgress(syncEngine.progress) }
        menuBarController?.updateProgress(syncEngine.progress)
        forEachWidget { $0.updateLyrics(lines: lines, currentIndex: index, words: syncEngine.currentWords) }
        forEachWidget { $0.updateWordProgresses(syncEngine.wordProgresses) }
        forEachWidget { $0.updateProgress(syncEngine.progress) }

        if playerManager.isPlaying {
            menuBarController?.updateCurrentLine(currentLine, isSynced: isSynced)
        }
        menuBarController?.updateLyrics(lines: lines, currentIndex: index)
    }

    // MARK: - Hotkey Actions

    private func toggleOverlayVisibility() {
        if isOverlayHidden {
            cancelAutoHide()
            showOverlay()
        } else {
            cancelAutoHide()
            hideOverlay()
        }
    }

    private func toggleAllDisplays() {
        allDisplaysHidden.toggle()
        if allDisplaysHidden {
            cancelAutoHide()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.overlayWindow?.animator().alphaValue = 0
                self.desktopWidget?.animator().alphaValue = 0
                for overlay in self.additionalOverlays { overlay.animator().alphaValue = 0 }
                for widget in self.additionalWidgets { widget.animator().alphaValue = 0 }
            }
            menuBarController?.updateCurrentLine("")
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.overlayWindow?.animator().alphaValue = 1
                self.desktopWidget?.animator().alphaValue = 1
                for overlay in self.additionalOverlays { overlay.animator().alphaValue = 1 }
                for widget in self.additionalWidgets { widget.animator().alphaValue = 1 }
            }
            isOverlayHidden = false
            lastDisplayedLineIndex = -2  // force redraw
            updateAllDisplays()
        }
    }

    private func nudgeOffset(_ delta: TimeInterval) {
        SettingsManager.shared.lyricsOffset += delta
    }

    private func resetOffset() {
        SettingsManager.shared.lyricsOffset = 0
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
        playerManager.stopPolling()
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        for w in additionalOverlays { w.orderOut(nil) }
        additionalOverlays.removeAll()
        for w in additionalWidgets { w.orderOut(nil) }
        additionalWidgets.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
}
