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
    private var highlightWordStack: WordStackView?
    private(set) var isEditMode = false
    private var editBorderLayer: CAShapeLayer?
    private(set) weak var currentScreen: NSScreen?
    private var backgroundEffect: NSVisualEffectView!

    init() {
        let settings = SettingsManager.shared
        visibleLines = settings.widgetLineCount
        currentHighlightIndex = visibleLines / 2

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 400
        let height = CGFloat(visibleLines) * 36 + 32
        let origin: NSPoint
        if AppConfig.get(AppConfig.Widget.hasCustomPosition) {
            let rx = CGFloat(AppConfig.get(AppConfig.Widget.customCenterX))
            let ry = CGFloat(AppConfig.get(AppConfig.Widget.customY))
            if rx > 1.0 || ry > 1.0 {
                origin = NSPoint(x: rx - width / 2, y: ry)
            } else {
                let abs = ScreenDetector.relativeToAbsolute(relativeX: rx, relativeY: ry, on: screen)
                origin = NSPoint(x: abs.centerX - width / 2, y: abs.originY)
            }
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
        currentScreen = screen
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
        if let ws = highlightWordStack {
            stackView.removeArrangedSubview(ws)
            ws.removeFromSuperview()
        }
        lineLabels.removeAll()
        highlightWordStack = nil
        gradientMask = nil

        for i in 0..<visibleLines {
            if i == currentHighlightIndex {
                let ws = WordStackView()
                ws.translatesAutoresizingMaskIntoConstraints = false
                highlightWordStack = ws
                lineLabels.append(NSTextField(labelWithString: ""))  // placeholder for index tracking
                stackView.addArrangedSubview(ws)
            } else {
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
    }

    func updateLineCount(_ count: Int) {
        guard count != visibleLines else { return }
        visibleLines = count
        currentHighlightIndex = count / 2
        gradientMask = nil  // old mask is orphaned after rebuild
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
                // WordStackView handles highlight theming
            } else {
                label.font = theme.nextLineFont
                label.textColor = theme.textColor.withAlphaComponent(theme.nextLineOpacity)
            }
        }

        if let ws = highlightWordStack {
            let wordTexts = ws.wordLabels.map { $0.stringValue }
            if !wordTexts.isEmpty {
                ws.setWords(
                    wordTexts,
                    font: theme.currentLineFont,
                    textColor: theme.textColor,
                    letterSpacing: theme.letterSpacing,
                    shadow: theme.textShadow,
                    karaokeFillEnabled: theme.karaokeFillEnabled
                )
            }
        }
    }

    func updateLyrics(lines: [LyricLine], currentIndex: Int, words: [String] = []) {
        let theme = ThemeManager.shared.theme
        let lineChanged = currentIndex != lastCurrentIndex
        lastCurrentIndex = currentIndex

        for i in 0..<visibleLines {
            if i == currentHighlightIndex {
                let lineIndex = currentIndex - currentHighlightIndex + i
                let text = (lineIndex >= 0 && lineIndex < lines.count) ? lines[lineIndex].text : ""
                if let ws = highlightWordStack {
                    let wordTexts = words.isEmpty ? (text.isEmpty ? [] : [text]) : words
                    if !wordTexts.isEmpty {
                        ws.setWords(
                            wordTexts,
                            font: theme.currentLineFont,
                            textColor: theme.textColor,
                            letterSpacing: theme.letterSpacing,
                            shadow: theme.textShadow,
                            karaokeFillEnabled: theme.karaokeFillEnabled
                        )
                    }
                }
                // Reset karaoke on line change
                if lineChanged, let ws = highlightWordStack {
                    ws.resetMasks(fillEdgeWidth: ThemeManager.shared.theme.fillEdgeWidth)
                }
                continue  // skip the normal label handling for this index
            }

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
                            label.animator().alphaValue = theme.nextLineOpacity
                        }
                    }
                } else {
                    lineLabels[i].stringValue = text
                }
            }

            lineLabels[i].font = theme.nextLineFont
            lineLabels[i].textColor = theme.textColor.withAlphaComponent(theme.nextLineOpacity)
        }
    }

    // MARK: - Karaoke Fill

    func updateWordProgresses(_ progresses: [Double]) {
        let theme = ThemeManager.shared.theme
        guard theme.karaokeFillEnabled, let ws = highlightWordStack else { return }
        ws.updateProgresses(progresses, fillEdgeWidth: theme.fillEdgeWidth, animated: true)
    }

    func updateProgress(_ progress: Double) {
        // Word-level progress handled by updateWordProgresses()
    }

    // MARK: - Multi-Display

    func moveToScreen(_ screen: NSScreen, animated: Bool = true) {
        guard screen !== currentScreen else { return }
        currentScreen = screen

        let width: CGFloat = 400
        let height = CGFloat(visibleLines) * 36 + 32
        let newSize = NSSize(width: width, height: height)

        let newOrigin: NSPoint
        if AppConfig.get(AppConfig.Widget.hasCustomPosition) {
            let rx = CGFloat(AppConfig.get(AppConfig.Widget.customCenterX))
            let ry = CGFloat(AppConfig.get(AppConfig.Widget.customY))
            if rx > 1.0 || ry > 1.0 {
                newOrigin = NSPoint(x: screen.frame.width - width - 40, y: 100)
            } else {
                let abs = ScreenDetector.relativeToAbsolute(relativeX: rx, relativeY: ry, on: screen)
                newOrigin = NSPoint(x: abs.centerX - width / 2, y: abs.originY)
            }
        } else {
            newOrigin = NSPoint(x: screen.frame.width - width - 40, y: 100)
        }

        let newFrame = NSRect(origin: newOrigin, size: newSize)

        if animated && alphaValue > 0 {
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

        AppConfig.set(AppConfig.Widget.hasCustomPosition, true)
        if let screen = self.screen ?? currentScreen {
            let rel = ScreenDetector.absoluteToRelative(centerX: frame.midX, originY: frame.origin.y, on: screen)
            AppConfig.set(AppConfig.Widget.customCenterX, rel.relativeX)
            AppConfig.set(AppConfig.Widget.customY, rel.relativeY)
        } else {
            AppConfig.set(AppConfig.Widget.customCenterX, frame.midX)
            AppConfig.set(AppConfig.Widget.customY, frame.origin.y)
        }

        isEditMode = false
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        editBorderLayer?.removeFromSuperlayer()
        editBorderLayer = nil
    }
}
