import AppKit
import QuartzCore
import Combine

class OverlayWindow: NSWindow {
    private let currentLabelA = NSTextField(labelWithString: "")
    private let currentLabelB = NSTextField(labelWithString: "")
    private let nextLyricLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private var useA = true

    private var currentTopA: NSLayoutConstraint!
    private var currentTopB: NSLayoutConstraint!

    private var container: NSView!
    private var backgroundView: NSVisualEffectView?
    private var backgroundLayer: CALayer?

    private let slideDistance: CGFloat = 12
    private let horizontalPadding: CGFloat = 16
    private let minOverlayWidth: CGFloat = 200
    private var cancellables = Set<AnyCancellable>()
    private var isAnimating = false
    private var isMouseInside = false
    private(set) var isEditMode = false
    private var editBorderLayer: CAShapeLayer?

    init() {
        let theme = ThemeManager.shared.theme
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: theme.overlayWidth, height: 90)

        // Use saved custom position if available, otherwise use preset
        let origin: NSPoint
        if UserDefaults.standard.bool(forKey: "overlay.hasCustomPosition") {
            let centerX = CGFloat(UserDefaults.standard.double(forKey: "overlay.customCenterX"))
            let y = CGFloat(UserDefaults.standard.double(forKey: "overlay.customY"))
            origin = NSPoint(x: centerX - size.width / 2, y: y)
        } else {
            origin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: size)
        }

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
        setupMouseTracking()
    }

    private func setupMouseTracking() {
        // Use a lightweight timer to check mouse position
        // Global event monitors can crash with animator() proxies
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.checkMousePosition()
            }
        }
    }

    private func checkMousePosition() {
        guard isVisible else { return }
        let mouseLocation = NSEvent.mouseLocation  // screen coordinates
        let inside = frame.contains(mouseLocation)

        guard inside != isMouseInside else { return }
        isMouseInside = inside

        // Direct alpha change — safer than animator() from timer context
        let targetAlpha: CGFloat = inside ? 1 : 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            self.sourceLabel.alphaValue = targetAlpha
        }
    }

    // MARK: - Edit Mode (toggle from menu bar)

    func toggleEditMode() {
        if isEditMode { lockPosition() } else { unlockPosition() }
    }

    private func unlockPosition() {
        isEditMode = true
        ignoresMouseEvents = false
        isMovableByWindowBackground = true

        // Show dashed border
        let border = CAShapeLayer()
        border.strokeColor = NSColor.white.withAlphaComponent(0.6).cgColor
        border.fillColor = nil
        border.lineDashPattern = [6, 4]
        border.lineWidth = 2
        border.path = CGPath(roundedRect: container.bounds.insetBy(dx: 1, dy: 1),
                             cornerWidth: 8, cornerHeight: 8, transform: nil)
        container.layer?.addSublayer(border)
        editBorderLayer = border
    }

    func lockPosition() {
        guard isEditMode else { return }

        // Save center X (not origin) so dynamic width doesn't shift position on reload
        UserDefaults.standard.set(true, forKey: "overlay.hasCustomPosition")
        UserDefaults.standard.set(frame.midX, forKey: "overlay.customCenterX")
        UserDefaults.standard.set(frame.origin.y, forKey: "overlay.customY")

        isEditMode = false
        ignoresMouseEvents = true
        isMovableByWindowBackground = false

        editBorderLayer?.removeFromSuperlayer()
        editBorderLayer = nil
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

        configureLabel(sourceLabel)
        sourceLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.3)
        sourceLabel.alignment = .right
        sourceLabel.alphaValue = 0

        container.addSubview(currentLabelA)
        container.addSubview(currentLabelB)
        container.addSubview(nextLyricLabel)
        container.addSubview(sourceLabel)

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

            sourceLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            sourceLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
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
        if isEditMode { return }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width = theme.backgroundStyle == .bar ? screen.frame.width : theme.overlayWidth
        let newSize = NSSize(width: width, height: 90)

        // Check for user-saved custom position (stored independently from theme)
        if UserDefaults.standard.bool(forKey: "overlay.hasCustomPosition") {
            let centerX = CGFloat(UserDefaults.standard.double(forKey: "overlay.customCenterX"))
            let y = CGFloat(UserDefaults.standard.double(forKey: "overlay.customY"))
            let x = centerX - newSize.width / 2
            setFrame(NSRect(origin: NSPoint(x: x, y: y), size: newSize), display: true)
            return
        }

        let origin: NSPoint
        if theme.backgroundStyle == .bar {
            let baseOrigin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: newSize)
            origin = NSPoint(x: screen.frame.minX, y: baseOrigin.y)
        } else {
            origin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: newSize)
        }
        setFrame(NSRect(origin: origin, size: newSize), display: true)
    }

    // MARK: - Dynamic Width

    private func measureTextWidth(_ text: String, font: NSFont, letterSpacing: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if letterSpacing != 0 {
            attrs[.kern] = letterSpacing
        }
        let size = (text as NSString).size(withAttributes: attrs)
        return ceil(size.width)
    }

    private func resizeToFit(currentText: String, nextText: String, animated: Bool) {
        let theme = ThemeManager.shared.theme

        // Bar mode stays full-width
        if theme.backgroundStyle == .bar { return }

        let currentWidth = measureTextWidth(currentText, font: theme.currentLineFont, letterSpacing: theme.letterSpacing)
        let nextWidth = measureTextWidth(nextText, font: theme.nextLineFont, letterSpacing: theme.letterSpacing)
        let textWidth = max(currentWidth, nextWidth)
        let targetWidth = min(
            theme.overlayWidth,
            max(minOverlayWidth, textWidth + horizontalPadding * 2)
        )

        let currentFrame = frame
        guard abs(currentFrame.width - targetWidth) > 2 else { return }

        // Keep horizontal center stable
        let centerX = currentFrame.midX
        let newOrigin = NSPoint(x: centerX - targetWidth / 2, y: currentFrame.origin.y)
        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: targetWidth, height: currentFrame.height))

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = theme.animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
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
            resizeToFit(currentText: current, nextText: next, animated: theme.transitionStyle != .none)

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
            let activeLabel = useA ? currentLabelA : currentLabelB
            resizeToFit(currentText: activeLabel.stringValue, nextText: next, animated: true)
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

    func updateSource(_ source: LyricsSource?) {
        let text: String
        switch source {
        case .lrclib: text = "via LRCLIB"
        case .spotify: text = "via Spotify"
        case .musixmatch: text = "via Musixmatch"
        case .netease: text = "via NetEase"
        case .plain: text = "plain text"
        case nil: text = ""
        }
        if sourceLabel.stringValue != text {
            sourceLabel.stringValue = text
        }
    }

    func showTrackInfo(title: String, artist: String) {
        updateLyrics(current: title, next: artist)
    }

}
