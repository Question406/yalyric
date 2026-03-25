import AppKit
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let spotifyBridge = SpotifyBridge()
    private let lyricsManager = LyricsManager()
    private let syncEngine = SyncEngine()

    private var overlayWindow: OverlayWindow?
    private var desktopWidget: DesktopWidget?
    private var menuBarController: MenuBarController?
    private var sidebarPanel: SidebarPanel?

    private var settingsWindowController: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar app
        NSApp.setActivationPolicy(.accessory)

        setupDisplayModes()
        setupBindings()
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

        if modes.contains(.sidebar) {
            if sidebarPanel == nil { sidebarPanel = SidebarPanel() }
            sidebarPanel?.orderFront(nil)
        } else {
            sidebarPanel?.orderOut(nil)
            sidebarPanel = nil
        }
    }

    private func setupMenuBarMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit LyricSync", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        menuBarController?.statusItem.menu = menu
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
                    self?.syncEngine.setLyrics(nil)
                    self?.updateAllDisplays()
                    return
                }
                self.lyricsManager.fetchLyrics(for: track)
            }
            .store(in: &cancellables)

        // When lyrics are fetched, update sync engine
        lyricsManager.$currentLyrics
            .sink { [weak self] lyrics in
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

        // React to playing state
        spotifyBridge.$isPlaying
            .sink { [weak self] playing in
                if !playing {
                    self?.menuBarController?.updateCurrentLine("")
                }
            }
            .store(in: &cancellables)
    }

    private func updateAllDisplays() {
        let currentLine = syncEngine.currentLine
        let nextLine = syncEngine.nextLine
        let index = syncEngine.currentLineIndex
        let lines = syncEngine.allLines

        // Overlay
        overlayWindow?.updateLyrics(current: currentLine, next: nextLine)

        // Desktop Widget
        desktopWidget?.updateLyrics(lines: lines, currentIndex: index)

        // Menu Bar
        if spotifyBridge.isPlaying {
            menuBarController?.updateCurrentLine(currentLine)
        }
        menuBarController?.updateLyrics(lines: lines, currentIndex: index)

        // Sidebar
        sidebarPanel?.updateLyrics(lines: lines, currentIndex: index)

        // Handle no track / no lyrics states
        if spotifyBridge.currentTrack == nil {
            overlayWindow?.updateLyrics(current: "", next: "")
        } else if lyricsManager.errorMessage != nil {
            overlayWindow?.updateLyrics(current: "♪ No lyrics found", next: "")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        spotifyBridge.stopPolling()
    }
}
