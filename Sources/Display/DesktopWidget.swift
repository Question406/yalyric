import AppKit
import Combine

class DesktopWidget: NSWindow {
    private let stackView = NSStackView()
    private var lineLabels: [NSTextField] = []
    private var visibleLines: Int
    private var currentHighlightIndex: Int
    private var cancellables = Set<AnyCancellable>()
    private var lastCurrentIndex: Int = -2
    private var gradientMask: CAGradientLayer?
    private(set) var isEditMode = false
    private var editBorderLayer: CAShapeLayer?
    private var backgroundEffect: NSVisualEffectView!

    init() {
        let settings = SettingsManager.shared
        visibleLines = settings.widgetLineCount
        currentHighlightIndex = visibleLines / 2

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 400
        let height = CGFloat(visibleLines) * 36 + 32
        let origin: NSPoint
        if UserDefaults.standard.bool(forKey: "widget.hasCustomPosition") {
            let cx = CGFloat(UserDefaults.standard.double(forKey: "widget.customCenterX"))
            let y = CGFloat(UserDefaults.standard.double(forKey: "widget.customY"))
            origin = NSPoint(x: cx - width / 2, y: y)
        } else {
            origin = NSPoint(x: screen.frame.width - width - 40, y: 100)
        }

        super.init(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.hasShadow = false
        self.ignoresMouseEvents = true

        setupContent()
        applyTheme(ThemeManager.shared.theme)
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

    private func setupContent() {
        backgroundEffect = NSVisualEffectView(frame: contentView!.bounds)
        backgroundEffect.autoresizingMask = [.width, .height]
        backgroundEffect.material = .hudWindow
        backgroundEffect.blendingMode = .behindWindow
        backgroundEffect.state = .active
        backgroundEffect.wantsLayer = true
        backgroundEffect.layer?.cornerRadius = 12
        backgroundEffect.layer?.masksToBounds = true

        stackView.orientation = .vertical
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        rebuildLabels()

        backgroundEffect.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: backgroundEffect.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: backgroundEffect.trailingAnchor, constant: -16),
            stackView.centerYAnchor.constraint(equalTo: backgroundEffect.centerYAnchor),
        ])

        contentView = backgroundEffect
    }

    private func rebuildLabels() {
        for label in lineLabels {
            stackView.removeArrangedSubview(label)
            label.removeFromSuperview()
        }
        lineLabels.removeAll()

        for _ in 0..<visibleLines {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.wantsLayer = true
            lineLabels.append(label)
            stackView.addArrangedSubview(label)
        }
    }

    func updateLineCount(_ count: Int) {
        guard count != visibleLines else { return }
        visibleLines = count
        currentHighlightIndex = count / 2
        rebuildLabels()
        applyTheme(ThemeManager.shared.theme)

        // Resize window height
        let height = CGFloat(visibleLines) * 36 + 32
        var f = frame
        f.size.height = height
        setFrame(f, display: true)
    }

    private func applyTheme(_ theme: Theme) {
        backgroundEffect.alphaValue = theme.backgroundOpacity

        for (i, label) in lineLabels.enumerated() {
            if i == currentHighlightIndex {
                label.font = theme.currentLineFont
                label.textColor = theme.textColor
            } else {
                label.font = theme.nextLineFont
                label.textColor = theme.textColor.withAlphaComponent(theme.nextLineOpacity)
            }
        }
        applyKaraokeFill(theme)
    }

    func updateLyrics(lines: [LyricLine], currentIndex: Int) {
        let theme = ThemeManager.shared.theme
        let lineChanged = currentIndex != lastCurrentIndex
        lastCurrentIndex = currentIndex

        // Reset karaoke fill on line change
        if lineChanged, let mask = gradientMask {
            mask.removeAnimation(forKey: "karaokeFill")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.locations = [0, 0, NSNumber(value: Float(theme.fillEdgeWidth)), 1]
            CATransaction.commit()
        }

        for i in 0..<visibleLines {
            let lineIndex = currentIndex - currentHighlightIndex + i
            let text = (lineIndex >= 0 && lineIndex < lines.count) ? lines[lineIndex].text : ""

            if lineLabels[i].stringValue != text {
                if lineChanged && theme.transitionStyle != .none {
                    // Crossfade on line change
                    let label = lineLabels[i]
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.15
                        label.animator().alphaValue = 0
                    } completionHandler: {
                        label.stringValue = text
                        NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = 0.15
                            label.animator().alphaValue = (i == self.currentHighlightIndex) ? 1.0 : theme.nextLineOpacity
                        }
                    }
                } else {
                    lineLabels[i].stringValue = text
                }
            }

            if i == currentHighlightIndex {
                lineLabels[i].font = theme.currentLineFont
                lineLabels[i].textColor = theme.textColor
            } else {
                lineLabels[i].font = theme.nextLineFont
                lineLabels[i].textColor = theme.textColor.withAlphaComponent(theme.nextLineOpacity)
            }
        }
    }

    // MARK: - Karaoke Fill

    private func applyKaraokeFill(_ theme: Theme) {
        let highlightLabel = lineLabels[currentHighlightIndex]
        if theme.karaokeFillEnabled {
            if gradientMask == nil {
                let mask = CAGradientLayer()
                mask.startPoint = CGPoint(x: 0, y: 0.5)
                mask.endPoint = CGPoint(x: 1, y: 0.5)
                mask.colors = [NSColor.white.cgColor, NSColor.white.cgColor,
                               NSColor.white.withAlphaComponent(0.35).cgColor,
                               NSColor.white.withAlphaComponent(0.35).cgColor]
                mask.locations = [0, 0, 0.001, 1]
                highlightLabel.layer?.mask = mask
                gradientMask = mask
            }
            gradientMask?.frame = highlightLabel.bounds
        } else {
            highlightLabel.layer?.mask = nil
            gradientMask = nil
        }
    }

    func updateProgress(_ progress: Double) {
        let theme = ThemeManager.shared.theme
        guard theme.karaokeFillEnabled else { return }

        let highlightLabel = lineLabels[currentHighlightIndex]
        guard let mask = highlightLabel.layer?.mask as? CAGradientLayer else { return }

        mask.frame = highlightLabel.bounds

        let p = Float(max(0, min(1, progress)))
        let edge = Float(theme.fillEdgeWidth)
        let newLocations: [NSNumber] = [0, NSNumber(value: p), NSNumber(value: p + edge), 1]

        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = mask.presentation()?.locations ?? mask.locations
        anim.toValue = newLocations
        anim.duration = 0.5
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.locations = newLocations
        CATransaction.commit()
        mask.add(anim, forKey: "karaokeFill")
    }

    // MARK: - Edit Mode (drag via menu bar toggle)

    func toggleEditMode() {
        if isEditMode { lockPosition() } else { unlockPosition() }
    }

    private func unlockPosition() {
        isEditMode = true
        ignoresMouseEvents = false
        isMovableByWindowBackground = true
        // Raise to floating level so mouse events work (desktop level doesn't receive drags)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let border = CAShapeLayer()
        border.strokeColor = NSColor.white.withAlphaComponent(0.6).cgColor
        border.fillColor = nil
        border.lineDashPattern = [6, 4]
        border.lineWidth = 2
        border.path = CGPath(roundedRect: backgroundEffect.bounds.insetBy(dx: 1, dy: 1),
                             cornerWidth: 12, cornerHeight: 12, transform: nil)
        backgroundEffect.layer?.addSublayer(border)
        editBorderLayer = border
    }

    func lockPosition() {
        guard isEditMode else { return }

        UserDefaults.standard.set(true, forKey: "widget.hasCustomPosition")
        UserDefaults.standard.set(frame.midX, forKey: "widget.customCenterX")
        UserDefaults.standard.set(frame.origin.y, forKey: "widget.customY")

        isEditMode = false
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        // Return to desktop level
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        editBorderLayer?.removeFromSuperlayer()
        editBorderLayer = nil
    }
}
