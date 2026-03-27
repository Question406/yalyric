import AppKit

class MenuBarController: NSObject, NSPopoverDelegate {
    let statusItem: NSStatusItem
    var contextMenu: NSMenu?  // set by AppDelegate
    private var popover: NSPopover?
    private var popoverScrollView: NSScrollView?
    private var popoverTextView: NSTextView?
    private var allLines: [LyricLine] = []
    private var currentIndex: Int = -1
    private var lyricsSource: LyricsSource?
    private var lyricsSynced: Bool = false
    private var userScrolling = false
    private var scrollResumeTimer: Timer?
    private var lastAutoScrollIndex: Int = -1

    private static let fallbackIcon = "♪ yalyric"

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            Self.applyIcon(to: button)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            if let menu = contextMenu {
                statusItem.menu = menu
                statusItem.button?.performClick(nil)
                DispatchQueue.main.async { self.statusItem.menu = nil }
            }
        } else {
            togglePopover()
        }
    }

    private static func applyIcon(to button: NSStatusBarButton) {
        if let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "yalyric") {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = fallbackIcon
        }
    }

    @objc private func togglePopover() {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        cleanupPopover()
    }

    private func cleanupPopover() {
        scrollResumeTimer?.invalidate()
        scrollResumeTimer = nil
        userScrolling = false
        if let sv = popoverScrollView {
            NotificationCenter.default.removeObserver(self, name: NSScrollView.willStartLiveScrollNotification, object: sv)
        }
        popover = nil
        popoverScrollView = nil
        popoverTextView = nil
    }

    private func showPopover() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 320, height: 400)
        pop.behavior = .transient
        pop.delegate = self

        let viewController = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))

        // Create fresh scroll view + text view each time
        let sv = NSScrollView(frame: container.bounds)
        sv.autoresizingMask = [.width, .height]
        sv.hasVerticalScroller = true
        sv.drawsBackground = false

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 296, height: 400))
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 296, height: CGFloat.greatestFiniteMagnitude)
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.font = NSFont.systemFont(ofSize: 14)
        tv.textColor = .labelColor
        tv.textContainerInset = NSSize(width: 12, height: 12)

        sv.documentView = tv
        container.addSubview(sv)

        viewController.view = container
        pop.contentViewController = viewController

        if let button = statusItem.button {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        self.popover = pop
        self.popoverScrollView = sv
        self.popoverTextView = tv
        userScrolling = false
        lastAutoScrollIndex = -1
        refreshTextView()

        NotificationCenter.default.addObserver(
            self, selector: #selector(userDidScroll),
            name: NSScrollView.willStartLiveScrollNotification, object: sv
        )
    }

    @objc private func userDidScroll() {
        userScrolling = true
        scrollResumeTimer?.invalidate()
        scrollResumeTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.userScrolling = false
        }
    }

    func updateCurrentLine(_ text: String, isSynced: Bool? = nil) {
        guard let button = statusItem.button else { return }

        if text.isEmpty {
            Self.applyIcon(to: button)
        } else {
            button.image = nil
            let prefix = isSynced == true ? "♪ " : isSynced == false ? "📄 " : ""
            let maxLen = 40 - prefix.count
            let truncated = text.count > maxLen ? String(text.prefix(maxLen - 3)) + "..." : text
            button.title = prefix + truncated
        }
    }

    func updateSource(_ source: LyricsSource?, isSynced: Bool) {
        self.lyricsSource = source
        self.lyricsSynced = isSynced
    }

    func updateLyrics(lines: [LyricLine], currentIndex: Int) {
        self.allLines = lines
        self.currentIndex = currentIndex
        if popover?.isShown == true {
            refreshTextView()
        }
    }

    func updateProgress(_ progress: Double) {
        // Karaoke fill is only in the overlay (GPU-accelerated).
        // Popover uses simple line highlighting — no per-character updates.
    }

    func popoverDidClose(_ notification: Notification) {
        cleanupPopover()
    }

    private func refreshTextView() {
        guard let textView = popoverTextView, let scrollView = popoverScrollView else { return }

        let attributed = NSMutableAttributedString()

        // Header
        if !allLines.isEmpty, let source = lyricsSource {
            let providerName: String
            switch source {
            case .lrclib: providerName = "LRCLIB"
            case .spotify: providerName = "Spotify"
            case .musixmatch: providerName = "Musixmatch"
            case .netease: providerName = "NetEase"
            case .plain: providerName = "plain"
            }
            let syncLabel = lyricsSynced ? "synced" : "plain text"
            let header = "\(allLines.count) lines · \(syncLabel) · \(providerName)\n\n"
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            attributed.append(NSAttributedString(string: header, attributes: headerAttrs))
        }

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 6
                return p
            }()
        ]
        let highlightAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: normalAttrs[.paragraphStyle]!
        ]

        for (i, line) in allLines.enumerated() {
            let attrs = (i == currentIndex) ? highlightAttrs : normalAttrs
            attributed.append(NSAttributedString(string: line.text + "\n", attributes: attrs))
        }

        textView.textStorage?.setAttributedString(attributed)

        // Auto-scroll
        if !userScrolling && currentIndex >= 0 && currentIndex < allLines.count && currentIndex != lastAutoScrollIndex {
            lastAutoScrollIndex = currentIndex
            let lineHeight: CGFloat = 24
            let y = CGFloat(currentIndex) * lineHeight
            let visibleHeight = scrollView.contentView.bounds.height
            let scrollY = max(0, y - visibleHeight / 2)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.allowsImplicitAnimation = true
                scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: scrollY))
            }
        }
    }
}
