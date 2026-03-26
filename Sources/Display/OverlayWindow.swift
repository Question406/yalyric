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
    private var isAnimating = false

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
            label.layer?.setAffineTransform(.identity)
            let str = NSMutableAttributedString(string: label.stringValue)
            if theme.letterSpacing != 0 {
                str.addAttribute(.kern, value: theme.letterSpacing, range: NSRange(location: 0, length: str.length))
            }
            label.attributedStringValue = str
        }

        nextLyricLabel.font = theme.nextLineFont
        nextLyricLabel.textColor = theme.textColor.withAlphaComponent(theme.nextLineOpacity)
        nextLyricLabel.shadow = shadow

        applyBackground(theme)
        applyPosition(theme)
    }

    private func applyBackground(_ theme: Theme) {
        backgroundView?.removeFromSuperview()
        backgroundView = nil
        backgroundLayer?.removeFromSuperlayer()
        backgroundLayer = nil

        switch theme.backgroundStyle {
        case .none:
            break

        case .frostedPill:
            let effect = NSVisualEffectView(frame: container.bounds)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.alphaValue = theme.backgroundOpacity
            effect.wantsLayer = true
            effect.layer?.cornerRadius = theme.backgroundCornerRadius
            effect.layer?.masksToBounds = true
            effect.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(effect, positioned: .below, relativeTo: currentLabelA)
            NSLayoutConstraint.activate([
                effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                effect.topAnchor.constraint(equalTo: container.topAnchor),
                effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            backgroundView = effect

        case .solidPill:
            let bg = NSView(frame: container.bounds)
            bg.wantsLayer = true
            bg.layer?.backgroundColor = theme.backgroundColor.cgColor
            bg.layer?.cornerRadius = theme.backgroundCornerRadius
            bg.alphaValue = theme.backgroundOpacity
            bg.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(bg, positioned: .below, relativeTo: currentLabelA)
            NSLayoutConstraint.activate([
                bg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bg.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bg.topAnchor.constraint(equalTo: container.topAnchor),
                bg.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            backgroundLayer = bg.layer

        case .bar:
            let effect = NSVisualEffectView(frame: container.bounds)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.alphaValue = theme.backgroundOpacity
            effect.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(effect, positioned: .below, relativeTo: currentLabelA)
            NSLayoutConstraint.activate([
                effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                effect.topAnchor.constraint(equalTo: container.topAnchor),
                effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            backgroundView = effect
        }
    }

    private func applyPosition(_ theme: Theme) {
        guard theme.overlayPosition != .custom else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width = theme.backgroundStyle == .bar ? screen.frame.width : theme.overlayWidth
        let newSize = NSSize(width: width, height: 90)
        let origin: NSPoint
        if theme.backgroundStyle == .bar {
            let baseOrigin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: newSize)
            origin = NSPoint(x: screen.frame.minX, y: baseOrigin.y)
        } else {
            origin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: newSize)
        }
        setFrame(NSRect(origin: origin, size: newSize), display: true)
    }

    // MARK: - Reset labels to clean state

    /// Cancel any in-flight animation and snap labels to a clean state
    private func resetLabelsToCleanState() {
        // Remove all animations
        currentLabelA.layer?.removeAllAnimations()
        currentLabelB.layer?.removeAllAnimations()

        let restY: CGFloat = 8
        let activeLabel = useA ? currentLabelA : currentLabelB
        let hiddenLabel = useA ? currentLabelB : currentLabelA
        let activeTop = useA ? currentTopA! : currentTopB!
        let hiddenTop = useA ? currentTopB! : currentTopA!

        // Snap: active visible at rest, hidden invisible at rest
        activeLabel.alphaValue = 1
        activeLabel.layer?.setAffineTransform(.identity)
        activeTop.constant = restY

        hiddenLabel.alphaValue = 0
        hiddenLabel.layer?.setAffineTransform(.identity)
        hiddenTop.constant = restY

        contentView?.layoutSubtreeIfNeeded()
        isAnimating = false
    }

    // MARK: - Lyrics Display

    func updateLyrics(current: String, next: String) {
        let theme = ThemeManager.shared.theme
        let activeLabel = useA ? currentLabelA : currentLabelB

        if activeLabel.stringValue != current {
            // If a previous animation is still running, snap to clean state first
            if isAnimating {
                resetLabelsToCleanState()
            }

            let incomingLabel = useA ? currentLabelB : currentLabelA
            let activeTop = useA ? currentTopA! : currentTopB!
            let incomingTop = useA ? currentTopB! : currentTopA!
            let restY: CGFloat = 8

            incomingLabel.stringValue = current

            switch theme.transitionStyle {
            case .none:
                activeLabel.alphaValue = 0
                activeLabel.layer?.setAffineTransform(.identity)
                activeTop.constant = restY
                incomingLabel.alphaValue = 1
                incomingLabel.layer?.setAffineTransform(.identity)
                incomingTop.constant = restY
                contentView?.layoutSubtreeIfNeeded()

            case .crossfade:
                incomingLabel.alphaValue = 0
                incomingTop.constant = restY
                activeTop.constant = restY
                contentView?.layoutSubtreeIfNeeded()
                isAnimating = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    activeLabel.animator().alphaValue = 0
                    incomingLabel.animator().alphaValue = 1
                } completionHandler: { [weak self] in
                    self?.isAnimating = false
                }

            case .slideUp:
                incomingLabel.alphaValue = 0
                incomingTop.constant = restY + slideDistance
                contentView?.layoutSubtreeIfNeeded()
                isAnimating = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    activeTop.constant = restY - slideDistance
                    activeLabel.animator().alphaValue = 0
                    incomingTop.constant = restY
                    incomingLabel.animator().alphaValue = 1
                    contentView?.layoutSubtreeIfNeeded()
                } completionHandler: { [weak self] in
                    self?.isAnimating = false
                }

            case .scaleFade:
                // Old line shrinks away, new line grows in from slightly larger
                incomingLabel.alphaValue = 0
                incomingTop.constant = restY
                activeTop.constant = restY
                contentView?.layoutSubtreeIfNeeded()

                // Incoming starts bigger than normal
                incomingLabel.layer?.setAffineTransform(CGAffineTransform(scaleX: 1.15, y: 1.15))

                isAnimating = true
                CATransaction.begin()
                CATransaction.setAnimationDuration(theme.animationDuration)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
                CATransaction.setCompletionBlock { [weak self] in
                    activeLabel.layer?.setAffineTransform(.identity)
                    self?.isAnimating = false
                }

                // Outgoing: shrink to 0.75 (noticeably smaller)
                activeLabel.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.75, y: 0.75))
                // Incoming: settle to normal size
                incomingLabel.layer?.setAffineTransform(.identity)

                CATransaction.commit()

                // Animate alpha via NSAnimationContext (works with animator proxy)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    activeLabel.animator().alphaValue = 0
                    incomingLabel.animator().alphaValue = 1
                }

            case .push:
                // Both labels visible, slide simultaneously with fade
                incomingLabel.alphaValue = 0
                incomingTop.constant = restY + slideDistance * 2
                contentView?.layoutSubtreeIfNeeded()
                isAnimating = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    activeTop.constant = restY - slideDistance * 2
                    activeLabel.animator().alphaValue = 0
                    incomingTop.constant = restY
                    incomingLabel.animator().alphaValue = 1
                    contentView?.layoutSubtreeIfNeeded()
                } completionHandler: { [weak self] in
                    self?.isAnimating = false
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
