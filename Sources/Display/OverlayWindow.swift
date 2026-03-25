import AppKit
import QuartzCore

class OverlayWindow: NSWindow {
    // Two label pairs that alternate for crossfade transitions
    private let currentLabelA = NSTextField(labelWithString: "")
    private let currentLabelB = NSTextField(labelWithString: "")
    private let nextLyricLabel = NSTextField(labelWithString: "")
    private var useA = true  // which label is currently visible

    private var currentTopA: NSLayoutConstraint!
    private var currentTopB: NSLayoutConstraint!

    private let slideDistance: CGFloat = 12
    private let animationDuration: TimeInterval = 0.3

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 800
        let height: CGFloat = 90
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

    private func makeLyricLabel(size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1.0) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = NSColor.white.withAlphaComponent(alpha)
        label.alignment = .center
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.wantsLayer = true
        label.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.8)
            s.shadowBlurRadius = 4
            s.shadowOffset = NSSize(width: 0, height: -1)
            return s
        }()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func setupContent() {
        let container = NSView(frame: contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true

        // Configure label A (starts visible)
        let labelA = currentLabelA
        labelA.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        labelA.textColor = .white
        labelA.alignment = .center
        labelA.maximumNumberOfLines = 1
        labelA.lineBreakMode = .byTruncatingTail
        labelA.isBezeled = false
        labelA.drawsBackground = false
        labelA.isEditable = false
        labelA.isSelectable = false
        labelA.wantsLayer = true
        labelA.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.8)
            s.shadowBlurRadius = 4
            s.shadowOffset = NSSize(width: 0, height: -1)
            return s
        }()
        labelA.translatesAutoresizingMaskIntoConstraints = false
        labelA.alphaValue = 1

        // Configure label B (starts hidden, positioned below)
        let labelB = currentLabelB
        labelB.font = labelA.font
        labelB.textColor = labelA.textColor
        labelB.alignment = labelA.alignment
        labelB.maximumNumberOfLines = 1
        labelB.lineBreakMode = .byTruncatingTail
        labelB.isBezeled = false
        labelB.drawsBackground = false
        labelB.isEditable = false
        labelB.isSelectable = false
        labelB.wantsLayer = true
        labelB.shadow = labelA.shadow
        labelB.translatesAutoresizingMaskIntoConstraints = false
        labelB.alphaValue = 0

        // Next line label
        let nextLabel = nextLyricLabel
        nextLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        nextLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        nextLabel.alignment = .center
        nextLabel.maximumNumberOfLines = 1
        nextLabel.lineBreakMode = .byTruncatingTail
        nextLabel.isBezeled = false
        nextLabel.drawsBackground = false
        nextLabel.isEditable = false
        nextLabel.isSelectable = false
        nextLabel.wantsLayer = true
        nextLabel.shadow = labelA.shadow
        nextLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(labelA)
        container.addSubview(labelB)
        container.addSubview(nextLabel)

        currentTopA = labelA.topAnchor.constraint(equalTo: container.topAnchor, constant: 8)
        currentTopB = labelB.topAnchor.constraint(equalTo: container.topAnchor, constant: 8 + slideDistance)

        NSLayoutConstraint.activate([
            labelA.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            labelA.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            currentTopA,

            labelB.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            labelB.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            currentTopB,

            nextLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            nextLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            nextLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 44),
        ])

        contentView = container
    }

    func updateLyrics(current: String, next: String) {
        let activeLabel = useA ? currentLabelA : currentLabelB
        let incomingLabel = useA ? currentLabelB : currentLabelA
        let activeTop = useA ? currentTopA! : currentTopB!
        let incomingTop = useA ? currentTopB! : currentTopA!

        let restY: CGFloat = 8

        // Only animate when the current line actually changes
        if activeLabel.stringValue != current {
            // Prepare incoming label: place it below, invisible, with new text
            incomingLabel.stringValue = current
            incomingLabel.alphaValue = 0
            incomingTop.constant = restY + slideDistance
            contentView?.layoutSubtreeIfNeeded()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true

                // Old label: slide up + fade out
                activeTop.constant = restY - slideDistance
                activeLabel.animator().alphaValue = 0

                // New label: slide up to center + fade in
                incomingTop.constant = restY
                incomingLabel.animator().alphaValue = 1

                contentView?.layoutSubtreeIfNeeded()
            }

            useA.toggle()
        }

        if nextLyricLabel.stringValue != next {
            // Subtle crossfade for next line
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                nextLyricLabel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.nextLyricLabel.stringValue = next
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    self?.nextLyricLabel.animator().alphaValue = 0.5
                }
            }
        }
    }

    func setDraggable(_ draggable: Bool) {
        ignoresMouseEvents = !draggable
    }
}
