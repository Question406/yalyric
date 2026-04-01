import AppKit
import QuartzCore
import Combine

class OverlayWindow: NSWindow {
    private let wordStackA = WordStackView()
    private let wordStackB = WordStackView()
    private let nextLyricLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private var useA = true
    private var currentLineTextA = ""
    private var currentLineTextB = ""

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
    private var mouseTrackingTimer: Timer?
    private var anchoredCenterX: CGFloat = 0  // stable center for resizeToFit
    private var lastTargetWidth: CGFloat = 0  // prevents redundant animations
    private(set) var isEditMode = false
    private var lastPositionKey: String = ""  // tracks position-related theme state
    private var editBorderLayer: CAShapeLayer?
    private(set) weak var currentScreen: NSScreen?

    init() {
        let theme = ThemeManager.shared.theme
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: theme.overlayWidth, height: 90)

        // Use saved custom position if available, otherwise use preset
        let origin: NSPoint
        if AppConfig.get(AppConfig.Overlay.hasCustomPosition) {
            let rx = CGFloat(AppConfig.get(AppConfig.Overlay.customCenterX))
            let ry = CGFloat(AppConfig.get(AppConfig.Overlay.customY))
            // If values are > 1.0, they're legacy absolute coords — convert
            if rx > 1.0 || ry > 1.0 {
                origin = NSPoint(x: rx - size.width / 2, y: ry)
                anchoredCenterX = rx
            } else {
                let abs = ScreenDetector.relativeToAbsolute(relativeX: rx, relativeY: ry, on: screen)
                origin = NSPoint(x: abs.centerX - size.width / 2, y: abs.originY)
                anchoredCenterX = abs.centerX
            }
        } else {
            origin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: size)
            anchoredCenterX = origin.x + size.width / 2
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
        currentScreen = screen
    }

    private func setupMouseTracking() {
        // Use a lightweight timer to check mouse position
        // Global event monitors can crash with animator() proxies
        mouseTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.checkMousePosition()
            }
        }
    }

    deinit {
        mouseTrackingTimer?.invalidate()
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

        anchoredCenterX = frame.midX
        AppConfig.set(AppConfig.Overlay.hasCustomPosition, true)

        // Save as relative coordinates for cross-screen compatibility
        if let screen = self.screen ?? currentScreen {
            let rel = ScreenDetector.absoluteToRelative(centerX: frame.midX, originY: frame.origin.y, on: screen)
            AppConfig.set(AppConfig.Overlay.customCenterX, rel.relativeX)
            AppConfig.set(AppConfig.Overlay.customY, rel.relativeY)
        } else {
            // Fallback: save absolute (legacy behavior)
            AppConfig.set(AppConfig.Overlay.customCenterX, anchoredCenterX)
            AppConfig.set(AppConfig.Overlay.customY, frame.origin.y)
        }

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

        wordStackA.translatesAutoresizingMaskIntoConstraints = false
        wordStackA.alphaValue = 1
        wordStackB.translatesAutoresizingMaskIntoConstraints = false
        wordStackB.alphaValue = 0
        configureLabel(nextLyricLabel)

        configureLabel(sourceLabel)
        sourceLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.3)
        sourceLabel.alignment = .right
        sourceLabel.alphaValue = 0

        container.addSubview(wordStackA)
        container.addSubview(wordStackB)
        container.addSubview(nextLyricLabel)
        container.addSubview(sourceLabel)

        currentTopA = wordStackA.topAnchor.constraint(equalTo: container.topAnchor, constant: 8)
        currentTopB = wordStackB.topAnchor.constraint(equalTo: container.topAnchor, constant: 8 + slideDistance)

        NSLayoutConstraint.activate([
            wordStackA.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            wordStackA.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            currentTopA,

            wordStackB.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            wordStackB.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
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

        for stack in [wordStackA, wordStackB] {
            let wordTexts = stack.wordLabels.map { $0.stringValue }
            if !wordTexts.isEmpty {
                stack.setWords(
                    wordTexts,
                    font: theme.currentLineFont,
                    textColor: theme.textColor,
                    letterSpacing: theme.letterSpacing,
                    shadow: shadow,
                    karaokeFillEnabled: theme.karaokeFillEnabled
                )
            }
        }

        nextLyricLabel.font = theme.nextLineFont
        nextLyricLabel.textColor = theme.textColor.withAlphaComponent(theme.nextLineOpacity)
        nextLyricLabel.shadow = shadow

        applyBackground(theme)

        // Only reposition when position-related properties change
        let posKey = "\(theme.overlayPosition.rawValue)|\(theme.overlayWidth)|\(theme.backgroundStyle.rawValue)"
        if posKey != lastPositionKey {
            lastPositionKey = posKey
            lastTargetWidth = 0  // force re-apply on next resize
            applyPosition(theme)
        }

        // Re-apply dynamic width with current text (handles font/size changes)
        let activeLineText = useA ? currentLineTextA : currentLineTextB
        resizeToFit(currentText: activeLineText, nextText: nextLyricLabel.stringValue, animated: false)
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
            container.addSubview(effect, positioned: .below, relativeTo: wordStackA)
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
            container.addSubview(bg, positioned: .below, relativeTo: wordStackA)
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
            container.addSubview(effect, positioned: .below, relativeTo: wordStackA)
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
        if AppConfig.get(AppConfig.Overlay.hasCustomPosition) {
            let rx = CGFloat(AppConfig.get(AppConfig.Overlay.customCenterX))
            let ry = CGFloat(AppConfig.get(AppConfig.Overlay.customY))
            let targetScreen = currentScreen ?? screen
            let centerX: CGFloat
            let y: CGFloat
            if rx > 1.0 || ry > 1.0 {
                centerX = rx
                y = ry
            } else {
                let abs = ScreenDetector.relativeToAbsolute(relativeX: rx, relativeY: ry, on: targetScreen)
                centerX = abs.centerX
                y = abs.originY
            }
            let x = centerX - newSize.width / 2
            anchoredCenterX = centerX
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
        anchoredCenterX = origin.x + newSize.width / 2
        setFrame(NSRect(origin: origin, size: newSize), display: true)
    }

    // MARK: - Multi-Display

    func moveToScreen(_ screen: NSScreen, animated: Bool = true) {
        guard screen !== currentScreen else { return }
        currentScreen = screen

        let theme = ThemeManager.shared.theme
        let width = theme.backgroundStyle == .bar ? screen.frame.width : theme.overlayWidth
        let newSize = NSSize(width: width, height: 90)

        let newOrigin: NSPoint
        if AppConfig.get(AppConfig.Overlay.hasCustomPosition) {
            let rx = CGFloat(AppConfig.get(AppConfig.Overlay.customCenterX))
            let ry = CGFloat(AppConfig.get(AppConfig.Overlay.customY))
            if rx > 1.0 || ry > 1.0 {
                // Legacy absolute — just use preset on new screen
                newOrigin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: newSize)
            } else {
                let abs = ScreenDetector.relativeToAbsolute(relativeX: rx, relativeY: ry, on: screen)
                newOrigin = NSPoint(x: abs.centerX - newSize.width / 2, y: abs.originY)
            }
        } else {
            if theme.backgroundStyle == .bar {
                let baseOrigin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: newSize)
                newOrigin = NSPoint(x: screen.frame.minX, y: baseOrigin.y)
            } else {
                newOrigin = theme.overlayPosition.defaultOrigin(for: screen, overlaySize: newSize)
            }
        }

        let newFrame = NSRect(origin: newOrigin, size: newSize)
        anchoredCenterX = newOrigin.x + newSize.width / 2

        if animated && alphaValue > 0 {
            // Crossfade: fade out → reposition → fade in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.setFrame(newFrame, display: true)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    self?.animator().alphaValue = 1
                }
            }
        } else {
            setFrame(newFrame, display: true)
        }
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
        if theme.backgroundStyle == .bar { return }

        let activeStack = useA ? wordStackA : wordStackB
        let currentWidth = activeStack.intrinsicTextWidth
        let nextWidth = measureTextWidth(nextText, font: theme.nextLineFont, letterSpacing: theme.letterSpacing)
        let textWidth = max(currentWidth + horizontalPadding * 2, nextWidth + horizontalPadding * 2)
        let targetWidth = min(theme.overlayWidth, max(minOverlayWidth, textWidth))

        guard abs(lastTargetWidth - targetWidth) > 2 else { return }
        lastTargetWidth = targetWidth

        let currentY = frame.origin.y
        let newOrigin = NSPoint(x: anchoredCenterX - targetWidth / 2, y: currentY)
        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: targetWidth, height: frame.height))

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

    // MARK: - Karaoke Fill

    func updateProgress(_ progress: Double) {
        // Word-level progress handled by updateWordProgresses()
    }

    func updateWordProgresses(_ progresses: [Double]) {
        let theme = ThemeManager.shared.theme
        guard theme.karaokeFillEnabled else { return }
        let activeStack = useA ? wordStackA : wordStackB
        activeStack.updateProgresses(progresses, fillEdgeWidth: theme.fillEdgeWidth, animated: true)
    }

    // MARK: - Reset labels to clean state

    /// Cancel any in-flight animation and snap labels to a clean state
    private func resetLabelsToCleanState() {
        wordStackA.layer?.removeAllAnimations()
        wordStackB.layer?.removeAllAnimations()

        let restY: CGFloat = 8
        let activeStack = useA ? wordStackA : wordStackB
        let hiddenStack = useA ? wordStackB : wordStackA
        let activeTop = useA ? currentTopA! : currentTopB!
        let hiddenTop = useA ? currentTopB! : currentTopA!

        activeStack.alphaValue = 1
        activeStack.layer?.setAffineTransform(.identity)
        activeTop.constant = restY

        hiddenStack.alphaValue = 0
        hiddenStack.layer?.setAffineTransform(.identity)
        hiddenTop.constant = restY

        contentView?.layoutSubtreeIfNeeded()
        isAnimating = false
    }

    // MARK: - Lyrics Display

    func updateLyrics(current: String, next: String, words: [String] = []) {
        let theme = ThemeManager.shared.theme
        let activeStack = useA ? wordStackA : wordStackB

        let activeLineText = useA ? currentLineTextA : currentLineTextB
        if activeLineText != current {
            // If a previous animation is still running, snap to clean state first
            if isAnimating {
                resetLabelsToCleanState()
            }

            let incomingStack = useA ? wordStackB : wordStackA
            let activeTop = useA ? currentTopA! : currentTopB!
            let incomingTop = useA ? currentTopB! : currentTopA!
            let restY: CGFloat = 8

            // Store the line text for future comparison
            if useA { currentLineTextB = current } else { currentLineTextA = current }

            let wordTexts = words.isEmpty ? [current] : words
            incomingStack.setWords(
                wordTexts,
                font: theme.currentLineFont,
                textColor: theme.textColor,
                letterSpacing: theme.letterSpacing,
                shadow: theme.textShadow,
                karaokeFillEnabled: theme.karaokeFillEnabled
            )
            resizeToFit(currentText: current, nextText: next, animated: theme.transitionStyle != .none)

            // Reset karaoke fill on the incoming stack to start from 0
            incomingStack.resetMasks(fillEdgeWidth: theme.fillEdgeWidth)

            switch theme.transitionStyle {
            case .none:
                activeStack.alphaValue = 0
                activeStack.layer?.setAffineTransform(.identity)
                activeTop.constant = restY
                incomingStack.alphaValue = 1
                incomingStack.layer?.setAffineTransform(.identity)
                incomingTop.constant = restY
                contentView?.layoutSubtreeIfNeeded()

            case .crossfade:
                incomingStack.alphaValue = 0
                incomingTop.constant = restY
                activeTop.constant = restY
                contentView?.layoutSubtreeIfNeeded()
                isAnimating = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    activeStack.animator().alphaValue = 0
                    incomingStack.animator().alphaValue = 1
                } completionHandler: { [weak self] in
                    self?.isAnimating = false
                }

            case .slideUp:
                incomingStack.alphaValue = 0
                incomingTop.constant = restY + slideDistance
                contentView?.layoutSubtreeIfNeeded()
                isAnimating = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    activeTop.constant = restY - slideDistance
                    activeStack.animator().alphaValue = 0
                    incomingTop.constant = restY
                    incomingStack.animator().alphaValue = 1
                    contentView?.layoutSubtreeIfNeeded()
                } completionHandler: { [weak self] in
                    self?.isAnimating = false
                }

            case .scaleFade:
                incomingStack.alphaValue = 0
                incomingTop.constant = restY
                activeTop.constant = restY
                contentView?.layoutSubtreeIfNeeded()

                incomingStack.layer?.setAffineTransform(CGAffineTransform(scaleX: 1.15, y: 1.15))

                isAnimating = true
                CATransaction.begin()
                CATransaction.setAnimationDuration(theme.animationDuration)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
                CATransaction.setCompletionBlock { [weak self] in
                    activeStack.layer?.setAffineTransform(.identity)
                    self?.isAnimating = false
                }

                activeStack.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.75, y: 0.75))
                incomingStack.layer?.setAffineTransform(.identity)

                CATransaction.commit()

                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    activeStack.animator().alphaValue = 0
                    incomingStack.animator().alphaValue = 1
                }

            case .push:
                incomingStack.alphaValue = 0
                incomingTop.constant = restY + slideDistance * 2
                contentView?.layoutSubtreeIfNeeded()
                isAnimating = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = theme.animationDuration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    activeTop.constant = restY - slideDistance * 2
                    activeStack.animator().alphaValue = 0
                    incomingTop.constant = restY
                    incomingStack.animator().alphaValue = 1
                    contentView?.layoutSubtreeIfNeeded()
                } completionHandler: { [weak self] in
                    self?.isAnimating = false
                }
            }

            useA.toggle()
        }

        if nextLyricLabel.stringValue != next {
            let activeLineText2 = useA ? currentLineTextA : currentLineTextB
            resizeToFit(currentText: activeLineText2, nextText: next, animated: true)
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

    func updateSource(_ source: LyricsSource?, isSynced: Bool = false) {
        let provider: String
        switch source {
        case .lrclib: provider = "LRCLIB"
        case .spotify: provider = "Spotify"
        case .musixmatch: provider = "Musixmatch"
        case .netease: provider = "NetEase"
        case .plain: provider = ""
        case nil: provider = ""
        }
        let text: String
        if provider.isEmpty {
            text = source == .plain ? "plain text" : ""
        } else {
            text = "via \(provider) · \(isSynced ? "synced" : "plain")"
        }
        if sourceLabel.stringValue != text {
            sourceLabel.stringValue = text
        }
    }

    func showTrackInfo(title: String, artist: String) {
        updateLyrics(current: title, next: artist)
    }

}
