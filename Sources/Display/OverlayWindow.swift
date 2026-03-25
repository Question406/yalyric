import AppKit

class OverlayWindow: NSWindow {
    private let lyricLabel = NSTextField(labelWithString: "")
    private let nextLyricLabel = NSTextField(labelWithString: "")
    private var isDragging = false
    private var dragOffset = NSPoint.zero

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 800
        let height: CGFloat = 80
        let x = (screen.frame.width - width) / 2
        let y: CGFloat = 120

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
        self.isMovableByWindowBackground = false

        setupContent()
    }

    private func setupContent() {
        let container = NSView(frame: contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true

        // Current line
        lyricLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        lyricLabel.textColor = .white
        lyricLabel.alignment = .center
        lyricLabel.maximumNumberOfLines = 1
        lyricLabel.lineBreakMode = .byTruncatingTail
        lyricLabel.isBezeled = false
        lyricLabel.drawsBackground = false
        lyricLabel.isEditable = false
        lyricLabel.isSelectable = false
        lyricLabel.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.8)
            s.shadowBlurRadius = 4
            s.shadowOffset = NSSize(width: 0, height: -1)
            return s
        }()

        // Next line (dimmer)
        nextLyricLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        nextLyricLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        nextLyricLabel.alignment = .center
        nextLyricLabel.maximumNumberOfLines = 1
        nextLyricLabel.lineBreakMode = .byTruncatingTail
        nextLyricLabel.isBezeled = false
        nextLyricLabel.drawsBackground = false
        nextLyricLabel.isEditable = false
        nextLyricLabel.isSelectable = false
        nextLyricLabel.shadow = lyricLabel.shadow

        lyricLabel.translatesAutoresizingMaskIntoConstraints = false
        nextLyricLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lyricLabel)
        container.addSubview(nextLyricLabel)

        NSLayoutConstraint.activate([
            lyricLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            lyricLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            lyricLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),

            nextLyricLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            nextLyricLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            nextLyricLabel.topAnchor.constraint(equalTo: lyricLabel.bottomAnchor, constant: 4),
        ])

        contentView = container
    }

    func updateLyrics(current: String, next: String) {
        // Only animate when the current line actually changes
        if lyricLabel.stringValue != current {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                lyricLabel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.lyricLabel.stringValue = current
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    self?.lyricLabel.animator().alphaValue = 1
                }
            }
        }
        if nextLyricLabel.stringValue != next {
            nextLyricLabel.stringValue = next
        }
    }

    /// Enable dragging by holding Option key
    func setDraggable(_ draggable: Bool) {
        ignoresMouseEvents = !draggable
    }
}
