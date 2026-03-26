import AppKit
import QuartzCore
import Combine

class OverlayWindow: NSWindow {
    private let currentLabelA = NSTextField(labelWithString: "")
    private let currentLabelB = NSTextField(labelWithString: "")
    private let nextLyricLabel = NSTextField(labelWithString: "")
    private var useA = true

    private var currentTopA: NSLayoutConstraint!
    private var currentTopB: NSLayoutConstraint!

    private var container: NSView!
    private var backgroundView: NSVisualEffectView?
    private var backgroundLayer: CALayer?

    private let slideDistance: CGFloat = 12
    private var cancellables = Set<AnyCancellable>()

    init() {
        let theme = ThemeManager.shared.theme
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: theme.overlayWidth, height: 90)
        let origin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: size)

        super.init(
            contentRect: NSRect(origin: origin, size: size),
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
        applyTheme(theme)
        observeTheme()
    }

    private func observeTheme() {
        ThemeManager.shared.$theme
            .receive(on: RunLoop.main)
            .sink { [weak self] theme in
                self?.applyTheme(theme)
            }
            .store(in: &cancellables)
    }

    private func configureLabel(_ label: NSTextField) {
        label.alignment = .center
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.wantsLayer = true
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupContent() {
        container = NSView(frame: contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true

        configureLabel(currentLabelA)
        currentLabelA.alphaValue = 1
        configureLabel(currentLabelB)
        currentLabelB.alphaValue = 0
        configureLabel(nextLyricLabel)

        container.addSubview(currentLabelA)
        container.addSubview(currentLabelB)
        container.addSubview(nextLyricLabel)

        currentTopA = currentLabelA.topAnchor.constraint(equalTo: container.topAnchor, constant: 8)
        currentTopB = currentLabelB.topAnchor.constraint(equalTo: container.topAnchor, constant: 8 + slideDistance)

        NSLayoutConstraint.activate([
            currentLabelA.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            currentLabelA.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            currentTopA,

            currentLabelB.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            currentLabelB.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            currentTopB,

            nextLyricLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            nextLyricLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            nextLyricLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 44),
        ])

        contentView = container
    }

    // MARK: - Theme Application

    func applyTheme(_ theme: Theme) {
        let shadow = theme.textShadow

        for label in [currentLabelA, currentLabelB] {
            label.font = theme.currentLineFont
            label.textColor = theme.textColor
            label.shadow = shadow
            if theme.letterSpacing != 0 {
                let str = NSMutableAttributedString(string: label.stringValue)
                str.addAttribute(.kern, value: theme.letterSpacing, range: NSRange(location: 0, length: str.length))
                label.attributedStringValue = str
            }
        }

        nextLyricLabel.font = theme.nextLineFont
        nextLyricLabel.textColor = theme.textColor.withAlphaComponent(theme.nextLineOpacity)
        nextLyricLabel.shadow = shadow

        applyBackground(theme)
        applyPosition(theme)
    }

    private func applyBackground(_ theme: Theme) {
        // Remove existing background
        backgroundView?.removeFromSuperview()
        backgroundView = nil
        backgroundLayer?.removeFromSuperlayer()
        backgroundLayer = nil

        switch theme.backgroundStyle {
        case .none:
            break
        case .pill:
            let bg = NSView(frame: container.bounds)
            bg.wantsLayer = true
            bg.layer?.backgroundColor = theme.backgroundColor.cgColor
            bg.layer?.cornerRadius = theme.backgroundCornerRadius
            bg.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(bg, positioned: .below, relativeTo: currentLabelA)
            NSLayoutConstraint.activate([
                bg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bg.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bg.topAnchor.constraint(equalTo: container.topAnchor),
                bg.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            let layer = bg.layer!
            backgroundLayer = layer
        case .bar:
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let barWidth = screen.frame.width
            let bg = NSView(frame: NSRect(x: 0, y: 0, width: barWidth, height: 90))
            bg.wantsLayer = true
            bg.layer?.backgroundColor = theme.backgroundColor.cgColor
            bg.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(bg, positioned: .below, relativeTo: currentLabelA)
            NSLayoutConstraint.activate([
                bg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bg.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bg.topAnchor.constraint(equalTo: container.topAnchor),
                bg.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            backgroundLayer = bg.layer
        }
    }

    private func applyPosition(_ theme: Theme) {
        guard theme.overlayPosition != .custom else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let newSize = NSSize(width: theme.overlayWidth, height: 90)
        let origin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: newSize)
        setFrame(NSRect(origin: origin, size: newSize), display: true)
    }

    // MARK: - Lyrics Display

    func updateLyrics(current: String, next: String) {
        let theme = ThemeManager.shared.theme
        let activeLabel = useA ? currentLabelA : currentLabelB
        let incomingLabel = useA ? currentLabelB : currentLabelA
        let activeTop = useA ? currentTopA! : currentTopB!
        let incomingTop = useA ? currentTopB! : currentTopA!

        let restY: CGFloat = 8

        if activeLabel.stringValue != current {
            incomingLabel.stringValue = current

            switch theme.transitionStyle {
            case .none:
                activeLabel.alphaValue = 0
                incomingLabel.alphaValue = 1
                activeTop.constant = restY
                incomingTop.constant = restY

            case .crossfade:
                incomingLabel.alphaValue = 0
                incomingTop.constant = restY
                contentView?.layoutSubtreeIfNeeded()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    activeLabel.animator().alphaValue = 0
                    incomingLabel.animator().alphaValue = 1
                }

            case .slideUp:
                incomingLabel.alphaValue = 0
                incomingTop.constant = restY + slideDistance
                contentView?.layoutSubtreeIfNeeded()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    activeTop.constant = restY - slideDistance
                    activeLabel.animator().alphaValue = 0
                    incomingTop.constant = restY
                    incomingLabel.animator().alphaValue = 1
                    contentView?.layoutSubtreeIfNeeded()
                }

            case .scaleFade:
                incomingLabel.alphaValue = 0
                incomingLabel.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.95, y: 0.95))
                incomingTop.constant = restY
                contentView?.layoutSubtreeIfNeeded()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    activeLabel.animator().alphaValue = 0
                    activeLabel.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.95, y: 0.95))
                    incomingLabel.animator().alphaValue = 1
                    incomingLabel.layer?.setAffineTransform(.identity)
                }

            case .push:
                incomingLabel.alphaValue = 1
                incomingTop.constant = restY + slideDistance * 2
                contentView?.layoutSubtreeIfNeeded()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    activeTop.constant = restY - slideDistance * 2
                    incomingTop.constant = restY
                    contentView?.layoutSubtreeIfNeeded()
                } completionHandler: {
                    activeLabel.alphaValue = 0
                }
            }

            useA.toggle()
        }

        if nextLyricLabel.stringValue != next {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                nextLyricLabel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self else { return }
                self.nextLyricLabel.stringValue = next
                let opacity = ThemeManager.shared.theme.nextLineOpacity
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.nextLyricLabel.animator().alphaValue = opacity
                }
            }
        }
    }

    func showTrackInfo(title: String, artist: String) {
        updateLyrics(current: title, next: artist)
    }

    func setDraggable(_ draggable: Bool) {
        ignoresMouseEvents = !draggable
    }
}
