import AppKit
import QuartzCore
import Combine

class OverlayWindow: NSWindow {
    private let currentLabelA = NSTextField(labelWithString: "")
    private let currentLabelB = NSTextField(labelWithString: "")
    private let nextLyricLabel = NSTextField(labelWithString: "")
    /// The line under the current one: the upcoming lyric, or a translation.
    var secondLineLabel: NSTextField { nextLyricLabel }
    /// Both halves of the current-line A/B pair, in no particular order.
    var currentLineLabels: [NSTextField] { [currentLabelA, currentLabelB] }
    private let sourceLabel = NSTextField(labelWithString: "")
    private var useA = true

    private var currentTopA: NSLayoutConstraint!
    private var currentTopB: NSLayoutConstraint!
    private var nextTop: NSLayoutConstraint!
    /// Vertical metrics for the current fonts; the text block is centred in `layout.height`.
    private var layout: OverlayLayout.Vertical

    private var container: NSView!
    private var backgroundView: NSVisualEffectView?
    private var backgroundLayer: CALayer?

    private let slideDistance: CGFloat = 12
    private var cancellables = Set<AnyCancellable>()
    private var isAnimating = false
    private var isMouseInside = false
    private var mouseTrackingTimer: Timer?
    private var anchoredCenterX: CGFloat = 0  // stable center for resizeToFit
    private var lastTargetWidth: CGFloat = 0  // prevents redundant animations
    /// Width for the whole track, computed once when lyrics load. While this is
    /// set the window never resizes on a line change.
    private var pinnedWidth: CGFloat?
    /// Kept so a font or width change can re-measure the same track.
    private var pinnedLyrics: Lyrics?
    private var pinnedSecondary: SecondaryLine = .nextLine
    private var frameAnimator: FrameAnimator!
    private(set) var isEditMode = false
    private var lastPositionKey: String = ""  // tracks position-related theme state
    private var editBorderLayer: CAShapeLayer?
    private(set) weak var currentScreen: NSScreen?
    private var currentScreenID: CGDirectDisplayID = 0

    // Karaoke fill gradient masks
    private var gradientMaskA: CAGradientLayer?
    private var gradientMaskB: CAGradientLayer?

    init() {
        let theme = ThemeManager.shared.theme
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let layout = Self.verticalLayout(for: theme)
        let frame = Self.resolvedFrame(theme: theme, on: screen, height: layout.height)
        self.layout = layout
        anchoredCenterX = frame.midX

        super.init(
            contentRect: frame,
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

        frameAnimator = FrameAnimator { [weak self] rect in
            self?.setFrame(rect, display: true)
        }
        frameAnimator.onComplete = { [weak self] in
            // Label bounds only settle now; realign the karaoke masks to the text
            self?.syncKaraokeMasks()
        }

        setupContent()
        applyTheme(theme)
        observeTheme()
        setupMouseTracking()
        currentScreen = screen
        currentScreenID = ScreenDetector.displayID(of: screen)
    }

    // MARK: - Frame Resolution

    /// The screen this overlay is tracking, looked up by display ID so it survives
    /// `NSScreen` instances being recreated on display changes.
    private var trackedScreen: NSScreen {
        NSScreen.screens.first { ScreenDetector.displayID(of: $0) == currentScreenID }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Reads the user's dragged position. Legacy absolute coordinates are migrated
    /// to relative ones once, so every code path interprets them the same way.
    private static func loadCustomPosition(migratingAgainst visibleFrame: NSRect) -> OverlayLayout.CustomPosition? {
        guard AppConfig.get(AppConfig.Overlay.hasCustomPosition) else { return nil }
        let rx = CGFloat(AppConfig.get(AppConfig.Overlay.customCenterX))
        let ry = CGFloat(AppConfig.get(AppConfig.Overlay.customY))
        let pos = OverlayLayout.customPosition(rawX: rx, rawY: ry, visibleFrame: visibleFrame)
        if pos.relativeX != rx || pos.relativeY != ry {
            AppConfig.set(AppConfig.Overlay.customCenterX, Double(pos.relativeX))
            AppConfig.set(AppConfig.Overlay.customY, Double(pos.relativeY))
        }
        return pos
    }

    /// Single source of truth for the window frame on a given screen. Used by
    /// `init`, `applyPosition` and `moveToScreen` so they can never disagree.
    private static func resolvedFrame(theme: Theme, on screen: NSScreen, height: CGFloat) -> NSRect {
        let migrationFrame = (NSScreen.main ?? screen).visibleFrame
        let custom = loadCustomPosition(migratingAgainst: migrationFrame)
        return OverlayLayout.frame(theme: theme, custom: custom,
                                   screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                                   height: height)
    }

    private static func verticalLayout(for theme: Theme) -> OverlayLayout.Vertical {
        let current = OverlayLayout.requiredLabelSize(for: "Ag", font: theme.currentLineFont, letterSpacing: 0).height
        let next = OverlayLayout.requiredLabelSize(for: "Ag", font: theme.nextLineFont, letterSpacing: 0).height
        return OverlayLayout.vertical(currentLineHeight: current, nextLineHeight: next)
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
            currentScreen = screen
            currentScreenID = ScreenDetector.displayID(of: screen)
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
        // The window frame must win over the text. NSWindow imposes its size at
        // priority 500 (windowSizeStayPut); a label's default compression
        // resistance of 750 outranks that, so a long line in the faded-out
        // label kept the window wide after every shrink and pushed it off centre.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
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

        currentTopA = currentLabelA.topAnchor.constraint(equalTo: container.topAnchor, constant: layout.currentTop)
        currentTopB = currentLabelB.topAnchor.constraint(equalTo: container.topAnchor, constant: layout.currentTop + slideDistance)
        nextTop = nextLyricLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: layout.nextTop)

        NSLayoutConstraint.activate([
            currentLabelA.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            currentLabelA.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            currentTopA,

            currentLabelB.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            currentLabelB.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            currentTopB,

            nextLyricLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            nextLyricLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            nextTop,

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
            label.attributedStringValue = OverlayLayout.attributedText(
                label.stringValue, font: theme.currentLineFont, letterSpacing: theme.letterSpacing)
        }

        nextLyricLabel.font = theme.nextLineFont
        // Opacity lives in `alphaValue` alone, never also in the text colour.
        // The two multiply: with the dimming baked into both, the label started
        // at 1.0 × 0.5 and fell to 0.5 × 0.5 the first time `updateLyrics`
        // faded it back in — a one-way brightness cliff on the first line
        // change. The current-line labels already follow this rule, which is
        // why they never showed the same fault.
        nextLyricLabel.textColor = theme.textColor
        nextLyricLabel.alphaValue = theme.nextLineOpacity
        nextLyricLabel.shadow = shadow
        nextLyricLabel.attributedStringValue = OverlayLayout.attributedText(
            nextLyricLabel.stringValue, font: theme.nextLineFont, letterSpacing: theme.letterSpacing)

        // Font changes move the text block; keep it centred in the window
        layout = Self.verticalLayout(for: theme)
        nextTop.constant = layout.nextTop
        if !isAnimating {
            currentTopA.constant = layout.currentTop
            currentTopB.constant = layout.currentTop
        }

        applyBackground(theme)

        // Only reposition when position-related properties change
        let posKey = "\(theme.overlayPosition.rawValue)|\(theme.overlayWidth)|\(theme.backgroundStyle.rawValue)|\(layout.height)"
        if posKey != lastPositionKey {
            lastPositionKey = posKey
            lastTargetWidth = 0  // force re-apply on next resize
            applyPosition(theme)
        }

        applyKaraokeFill(theme)

        // Re-apply width for the new fonts. A pinned track is re-measured
        // rather than resized to the current line, so a font change cannot
        // quietly reintroduce per-line sizing.
        if pinnedLyrics != nil {
            pinTrackWidth(for: pinnedLyrics, secondary: pinnedSecondary)
        } else {
            let activeLabel = useA ? currentLabelA : currentLabelB
            resizeToFit(currentText: activeLabel.stringValue, nextText: nextLyricLabel.stringValue, animated: false)
        }
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
        // Position on the screen we are tracking, not NSScreen.main: after a theme
        // change on a secondary display the window used to jump to the main screen
        // and moveToScreen's display-ID guard then refused to bring it back.
        let frame = Self.resolvedFrame(theme: theme, on: trackedScreen, height: layout.height)
        frameAnimator.cancel()
        anchoredCenterX = frame.midX
        lastTargetWidth = 0
        setFrame(frame, display: true)
    }

    // MARK: - Multi-Display

    func moveToScreen(_ screen: NSScreen, animated: Bool = true) {
        let targetID = ScreenDetector.displayID(of: screen)
        guard targetID != currentScreenID else { return }
        currentScreen = screen
        currentScreenID = targetID

        let theme = ThemeManager.shared.theme
        let newFrame = Self.resolvedFrame(theme: theme, on: screen, height: layout.height)

        // The anchor moves only when the window does. Updating it before the
        // fade-out let a lyric resize animate the window across displays.
        let place = { [weak self] in
            guard let self else { return }
            self.frameAnimator.cancel()
            self.anchoredCenterX = newFrame.midX
            self.setFrame(newFrame, display: true)
            // Restore the width immediately instead of waiting for the next line
            self.lastTargetWidth = 0
            if self.pinnedWidth != nil {
                self.applyPinnedWidth()
            } else {
                let activeLabel = self.useA ? self.currentLabelA : self.currentLabelB
                self.resizeToFit(currentText: activeLabel.stringValue, nextText: self.nextLyricLabel.stringValue, animated: false)
            }
        }

        if animated && alphaValue > 0 {
            // Crossfade: fade out → reposition → fade in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                place()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    self?.animator().alphaValue = 1
                }
            }
        } else {
            place()
        }
    }

    // MARK: - Dynamic Width

    /// Sizes the overlay for an entire track, once.
    ///
    /// Following the text meant resizing 75–175pt on every line change: smooth
    /// at 60fps, but the pill grew and shrank and the centred lyric slid
    /// sideways through each crossfade. Measuring the track up front removes
    /// the motion completely. Passing nil restores per-line sizing.
    func pinTrackWidth(for lyrics: Lyrics?, secondary: SecondaryLine) {
        pinnedLyrics = lyrics
        pinnedSecondary = secondary
        guard let lyrics, !lyrics.lines.isEmpty else {
            pinnedWidth = nil
            return
        }
        let theme = ThemeManager.shared.theme
        let secondaryTexts: [String]
        switch secondary {
        // The upcoming lyric is another line of the same track, so it is
        // already accounted for by the line texts themselves.
        case .nextLine:    secondaryTexts = []
        case .translation: secondaryTexts = lyrics.lines.compactMap(\.translation)
        case .romaji:      secondaryTexts = lyrics.lines.compactMap(\.romaji)
        }
        pinnedWidth = OverlayLayout.trackWidth(
            lineTexts: lyrics.lines.map(\.text), secondaryTexts: secondaryTexts,
            currentFont: theme.currentLineFont, nextFont: theme.nextLineFont,
            letterSpacing: theme.letterSpacing, maxWidth: theme.overlayWidth)
        applyPinnedWidth()
    }

    private func applyPinnedWidth() {
        guard let pinnedWidth,
              ThemeManager.shared.theme.backgroundStyle != .bar else { return }
        lastTargetWidth = pinnedWidth
        frameAnimator.cancel()
        setFrame(NSRect(x: anchoredCenterX - pinnedWidth / 2, y: frame.origin.y,
                        width: pinnedWidth, height: layout.height), display: true)
        contentView?.layoutSubtreeIfNeeded()
        syncKaraokeMasks()
    }

    private func resizeToFit(currentText: String, nextText: String, animated: Bool) {
        let theme = ThemeManager.shared.theme

        // Bar mode stays full-width
        if theme.backgroundStyle == .bar { return }
        // The track's width is fixed; no line may move it.
        if pinnedWidth != nil { return }

        // Measure what the label needs, not the bare glyph run: NSTextFieldCell
        // pads the text, and a label sized to the glyph width truncates with "…".
        let currentWidth = OverlayLayout.requiredLabelWidth(for: currentText, font: theme.currentLineFont, letterSpacing: theme.letterSpacing)
        let nextWidth = OverlayLayout.requiredLabelWidth(for: nextText, font: theme.nextLineFont, letterSpacing: theme.letterSpacing)
        let targetWidth = OverlayLayout.windowWidth(currentTextWidth: currentWidth, nextTextWidth: nextWidth, maxWidth: theme.overlayWidth)

        // Skip if target hasn't changed — prevents redundant animations
        guard abs(lastTargetWidth - targetWidth) > 2 else { return }
        lastTargetWidth = targetWidth

        let newOrigin = NSPoint(x: anchoredCenterX - targetWidth / 2, y: frame.origin.y)
        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: targetWidth, height: layout.height))

        if animated {
            frameAnimator.animate(from: frame, to: newFrame, duration: theme.animationDuration)
        } else {
            frameAnimator.cancel()
            setFrame(newFrame, display: true)
            contentView?.layoutSubtreeIfNeeded()
            syncKaraokeMasks()
        }
    }

    // MARK: - Karaoke Fill

    private func setupGradientMask(for label: NSTextField) -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        // Start fully dim (unfilled)
        gradient.colors = [NSColor.white.cgColor, NSColor.white.cgColor,
                           NSColor.white.withAlphaComponent(0.35).cgColor,
                           NSColor.white.withAlphaComponent(0.35).cgColor]
        gradient.locations = [0, 0, 0.001, 1]
        return gradient
    }

    private func applyKaraokeFill(_ theme: Theme) {
        if theme.karaokeFillEnabled {
            // Ensure layout is current before reading bounds
            contentView?.layoutSubtreeIfNeeded()

            // Create masks if needed
            if gradientMaskA == nil {
                let mask = setupGradientMask(for: currentLabelA)
                currentLabelA.layer?.mask = mask
                gradientMaskA = mask
            }
            if gradientMaskB == nil {
                let mask = setupGradientMask(for: currentLabelB)
                currentLabelB.layer?.mask = mask
                gradientMaskB = mask
            }
            syncKaraokeMasks()
        } else {
            // Remove masks
            currentLabelA.layer?.mask = nil
            currentLabelB.layer?.mask = nil
            gradientMaskA = nil
            gradientMaskB = nil
        }
    }

    /// Aligns each gradient mask with its label's text rather than the whole
    /// label, so the fill starts at the first glyph and ends at the last one.
    private func syncKaraokeMasks() {
        syncMask(gradientMaskA, to: currentLabelA)
        syncMask(gradientMaskB, to: currentLabelB)
    }

    private func syncMask(_ mask: CAGradientLayer?, to label: NSTextField) {
        guard let mask else { return }
        let theme = ThemeManager.shared.theme
        let textWidth = OverlayLayout.requiredLabelWidth(for: label.stringValue, font: theme.currentLineFont, letterSpacing: theme.letterSpacing)
        let target = OverlayLayout.karaokeMaskFrame(labelBounds: label.bounds, textWidth: textWidth)
        guard mask.frame != target else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = target
        CATransaction.commit()
    }

    func updateProgress(_ progress: Double) {
        let theme = ThemeManager.shared.theme
        guard theme.karaokeFillEnabled else { return }

        let activeLabel = useA ? currentLabelA : currentLabelB
        guard let mask = activeLabel.layer?.mask as? CAGradientLayer else { return }

        syncMask(mask, to: activeLabel)

        let p = Float(max(0, min(1, progress)))
        let edge = Float(theme.fillEdgeWidth)
        let newLocations: [NSNumber] = [0, NSNumber(value: p), NSNumber(value: p + edge), 1]

        // Animate smoothly between poll updates (0.5s interval)
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = mask.presentation()?.locations ?? mask.locations
        anim.toValue = newLocations
        anim.duration = 0.5
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards

        // Set model value and add animation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.locations = newLocations
        CATransaction.commit()
        mask.add(anim, forKey: "karaokeFill")
    }

    // MARK: - Reset labels to clean state

    /// Cancel any in-flight animation and snap labels to a clean state
    private func resetLabelsToCleanState() {
        // Remove all animations (including karaoke fill on masks)
        currentLabelA.layer?.removeAllAnimations()
        currentLabelB.layer?.removeAllAnimations()
        gradientMaskA?.removeAnimation(forKey: "karaokeFill")
        gradientMaskB?.removeAnimation(forKey: "karaokeFill")

        let restY = layout.currentTop
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
            let restY = layout.currentTop

            // The A/B pair recycles the outgoing label as the next incoming one.
            // When a line change interrupts a transition still in flight, that
            // label is on screen at around half opacity, and writing the new
            // text into it substitutes the previous line in place rather than
            // fading it out. Hide it first, with implicit animations suppressed:
            // CoreAnimation starts a new animation from the *presentation* value,
            // so a plain `alphaValue = 0` here is smoothed straight over and the
            // swap stays visible. Playback polls every 0.5s and the transition
            // also runs 0.5s, so these collide regularly rather than rarely.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            incomingLabel.layer?.removeAllAnimations()
            incomingLabel.alphaValue = 0
            CATransaction.commit()
            // Commit alone only updates the model; the presentation layer still
            // reports the mid-fade value until the next runloop turn, and that
            // is exactly what `animator()` uses as its fromValue. Flush so the
            // presentation catches up before the new animation is built.
            CATransaction.flush()

            incomingLabel.attributedStringValue = OverlayLayout.attributedText(
                current, font: theme.currentLineFont, letterSpacing: theme.letterSpacing)
            resizeToFit(currentText: current, nextText: next, animated: theme.transitionStyle != .none)

            // Reset karaoke fill on the incoming label to start from 0
            if let mask = incomingLabel.layer?.mask as? CAGradientLayer {
                mask.removeAnimation(forKey: "karaokeFill")
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                mask.locations = [0, 0, NSNumber(value: Float(theme.fillEdgeWidth)), 1]
                CATransaction.commit()
                syncMask(mask, to: incomingLabel)
            }

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
                let theme = ThemeManager.shared.theme
                self.nextLyricLabel.attributedStringValue = OverlayLayout.attributedText(
                    next, font: theme.nextLineFont, letterSpacing: theme.letterSpacing)
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
        case .kugou: provider = "Kugou"
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
