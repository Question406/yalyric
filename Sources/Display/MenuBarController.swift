import AppKit

class MenuBarController: NSObject {
    let statusItem: NSStatusItem
    private var popover: NSPopover?
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var allLines: [LyricLine] = []
    private var currentIndex: Int = -1

    private static let fallbackIcon = "♪ yalyric"

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            Self.applyIcon(to: button)
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
            popover.performClose(nil)
            self.popover = nil
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient

        let viewController = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))

        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 12, height: 12)

        scrollView.documentView = textView
        container.addSubview(scrollView)

        viewController.view = container
        popover.contentViewController = viewController

        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        self.popover = popover
        refreshTextView()
    }

    func updateCurrentLine(_ text: String) {
        guard let button = statusItem.button else { return }

        if text.isEmpty {
            Self.applyIcon(to: button)
        } else {
            button.image = nil
            let truncated = text.count > 40 ? String(text.prefix(37)) + "..." : text
            button.title = truncated
        }
    }

    func updateLyrics(lines: [LyricLine], currentIndex: Int) {
        self.allLines = lines
        self.currentIndex = currentIndex
        if popover?.isShown == true {
            refreshTextView()
        }
    }

    private func refreshTextView() {
        let attributed = NSMutableAttributedString()
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

        // Auto-scroll to current line
        if currentIndex >= 0 && currentIndex < allLines.count {
            let lineHeight: CGFloat = 24
            let y = CGFloat(currentIndex) * lineHeight
            let visibleHeight = scrollView.contentView.bounds.height
            let scrollY = max(0, y - visibleHeight / 2)
            textView.scroll(NSPoint(x: 0, y: scrollY))
        }
    }
}
