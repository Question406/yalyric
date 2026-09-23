import AppKit
import SwiftUI

// MARK: - Sample text

/// Placeholder lines for the Appearance preview — written for this stage, never
/// real song lyrics. Deliberately mixed-script: Han glyphs carry very different
/// metrics from Latin ones, so a Latin-only sample makes the font and
/// letter-spacing sliders lie about half the tracks this app is used on.
enum LyricPreviewSample {
    static let lines: [String] = [
        "Neon hums in the alley",
        "we fold the map at dawn",
        "夜风翻过窗台",
    ]

    static func line(at index: Int) -> String {
        guard lines.indices.contains(index) else { return lines[0] }
        return lines[index]
    }

    static func advance(_ index: Int) -> Int {
        guard lines.count > 1, lines.indices.contains(index) else { return 0 }
        return (index + 1) % lines.count
    }
}

// MARK: - When to animate

/// The preview holds still for style edits and only moves for settings that are
/// themselves about motion. Dragging a font slider while the stage loops is
/// unreadable; picking a transition without seeing it play is useless.
enum LyricPreviewTrigger {
    static func needsDemo(from old: Theme, to new: Theme) -> Bool {
        let motionChanged = old.transitionStyle != new.transitionStyle
            || old.animationDuration != new.animationDuration
            || old.karaokeFillEnabled != new.karaokeFillEnabled
            || old.fillEdgeWidth != new.fillEdgeWidth
        guard motionChanged else { return false }
        // "None" with no fill has nothing to show; a demo would only flicker.
        return new.transitionStyle != .none || new.karaokeFillEnabled
    }
}

// MARK: - Fitting the stage

enum LyricPreviewFit {
    /// The stage is a few hundred points wide; the real overlay may be 1600.
    /// Rather than truncate text the overlay would have drawn in full, the pill
    /// is measured at its true size and then zoomed to fit. Truncation still
    /// shows through when `overlayWidth` itself is the binding constraint,
    /// which is the case worth seeing.
    static func scale(desiredWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard desiredWidth > 0, availableWidth > 0 else { return 1 }
        return min(1, availableWidth / desiredWidth)
    }
}

// MARK: - Karaoke gradient stops

enum LyricPreviewFill {
    /// Where the fill rests when nothing is animating, so "Edge softness" stays
    /// legible on a stage that is standing still.
    static let restProgress: Double = 0.55

    /// `CAGradientLayer` needs non-decreasing stops inside 0...1. Near the end of
    /// a line `progress + edgeWidth` runs past 1, so the soft edge collapses
    /// rather than pushing a stop out of range.
    static func locations(progress: Double, edgeWidth: CGFloat) -> [CGFloat] {
        let p = min(max(0, CGFloat(progress)), 1)
        let edge = min(max(0, edgeWidth), 1)
        return [0, p, min(1, p + edge), 1]
    }
}

// MARK: - The stage

/// Draws the same two-line block the overlay does, at real point sizes, inside
/// the Appearance tab.
///
/// This mirrors `OverlayWindow`'s drawing rules rather than sharing them: that
/// class welds its rendering to `NSWindow` frame, screen and edit-mode logic,
/// and carries a long tail of hard-won fixes that are not worth destabilising
/// for a preview. The cost is that the two can drift — the text metrics at least
/// come from the shared, tested `OverlayLayout`.
final class LyricPreviewStage: NSView {

    private let backdrop = CAGradientLayer()
    private let pill = NSView()
    private let currentA = NSTextField(labelWithString: "")
    private let currentB = NSTextField(labelWithString: "")
    private let secondLabel = NSTextField(labelWithString: "")

    private var backgroundEffect: NSVisualEffectView?
    private var backgroundFill: NSView?
    private var maskA: CAGradientLayer?
    private var maskB: CAGradientLayer?

    private var pillWidth: NSLayoutConstraint!
    private var pillHeight: NSLayoutConstraint!
    private var currentTopA: NSLayoutConstraint!
    private var currentTopB: NSLayoutConstraint!
    private var secondTop: NSLayoutConstraint!

    private var metrics = OverlayLayout.vertical(currentLineHeight: 28, nextLineHeight: 19)
    private var theme = Theme()
    private var hasTheme = false
    private var useA = true
    private var lineIndex = 0
    private var replayToken = 0

    private var demoTimer: Timer?
    private var demoStepsLeft = 0
    private let slideDistance: CGFloat = 12
    /// Enough cycles to read the transition without the tab turning into a sign.
    private let demoSteps = 3

    // MARK: Setup

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 170))
        wantsLayer = true
        layer?.masksToBounds = true

        // A stand-in wallpaper: transparent and frosted styles are invisible
        // against a flat settings background, and so are text shadows.
        backdrop.colors = [
            NSColor(red: 0.14, green: 0.15, blue: 0.24, alpha: 1).cgColor,
            NSColor(red: 0.29, green: 0.20, blue: 0.34, alpha: 1).cgColor,
            NSColor(red: 0.16, green: 0.24, blue: 0.31, alpha: 1).cgColor,
        ]
        backdrop.startPoint = CGPoint(x: 0, y: 0)
        backdrop.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(backdrop)

        pill.wantsLayer = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        configureLabel(currentA)
        configureLabel(currentB)
        configureLabel(secondLabel)
        currentA.alphaValue = 1
        currentB.alphaValue = 0
        pill.addSubview(currentA)
        pill.addSubview(currentB)
        pill.addSubview(secondLabel)

        pillWidth = pill.widthAnchor.constraint(equalToConstant: 400)
        pillHeight = pill.heightAnchor.constraint(equalToConstant: metrics.height)
        currentTopA = currentA.topAnchor.constraint(equalTo: pill.topAnchor, constant: metrics.currentTop)
        currentTopB = currentB.topAnchor.constraint(equalTo: pill.topAnchor, constant: metrics.currentTop)
        secondTop = secondLabel.topAnchor.constraint(equalTo: pill.topAnchor, constant: metrics.nextTop)

        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillWidth, pillHeight,
            currentTopA, currentTopB, secondTop,
        ])
        for label in [currentA, currentB, secondLabel] {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: pill.leadingAnchor,
                                               constant: OverlayLayout.horizontalPadding),
                label.trailingAnchor.constraint(equalTo: pill.trailingAnchor,
                                                constant: -OverlayLayout.horizontalPadding),
            ])
        }

        currentA.stringValue = LyricPreviewSample.line(at: 0)
        secondLabel.stringValue = LyricPreviewSample.line(at: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { demoTimer?.invalidate() }

    /// Same configuration as the overlay's labels, including the compression
    /// resistance that keeps a long line from forcing the container wider.
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
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        CATransaction.commit()
        applyWidth()
        syncMasks()
    }

    // MARK: Updates from SwiftUI

    func update(theme newTheme: Theme, replayToken token: Int) {
        let replayRequested = token != replayToken
        replayToken = token

        let changed = !hasTheme || newTheme != theme
        let wantsDemo = hasTheme && LyricPreviewTrigger.needsDemo(from: theme, to: newTheme)
        theme = newTheme
        hasTheme = true

        if changed { applyStyle() }

        if wantsDemo || (replayRequested && (newTheme.transitionStyle != .none || newTheme.karaokeFillEnabled)) {
            startDemo()
        } else if changed && !isDemoRunning {
            settle()
        }
    }

    private var isDemoRunning: Bool { demoTimer != nil }

    // MARK: Style

    private func applyStyle() {
        let shadow = theme.textShadow

        for label in [currentA, currentB] {
            label.font = theme.currentLineFont
            label.textColor = theme.textColor
            label.shadow = shadow
            label.attributedStringValue = OverlayLayout.attributedText(
                label.stringValue, font: theme.currentLineFont, letterSpacing: theme.letterSpacing)
        }
        // Dimming lives in `alphaValue` alone, never also in the colour — the two
        // multiply, which is the cliff the overlay hit on its first line change.
        secondLabel.font = theme.nextLineFont
        secondLabel.textColor = theme.textColor
        secondLabel.alphaValue = theme.nextLineOpacity
        secondLabel.shadow = shadow
        secondLabel.attributedStringValue = OverlayLayout.attributedText(
            secondLabel.stringValue, font: theme.nextLineFont, letterSpacing: theme.letterSpacing)

        metrics = Self.verticalLayout(for: theme)
        pillHeight.constant = metrics.height
        secondTop.constant = metrics.nextTop
        if !isDemoRunning {
            currentTopA.constant = metrics.currentTop
            currentTopB.constant = metrics.currentTop
        }

        applyBackground()
        applyWidth()
        applyKaraoke()
    }

    private static func verticalLayout(for theme: Theme) -> OverlayLayout.Vertical {
        let current = OverlayLayout.requiredLabelSize(for: "Ag", font: theme.currentLineFont, letterSpacing: 0).height
        let next = OverlayLayout.requiredLabelSize(for: "Ag", font: theme.nextLineFont, letterSpacing: 0).height
        return OverlayLayout.vertical(currentLineHeight: current, nextLineHeight: next)
    }

    /// The overlay sizes itself once per track and clamps at `overlayWidth`; the
    /// stage does the same over the sample lines, so the pill hugs the text and
    /// the width slider bites exactly where it would in the real thing. A bar
    /// spans the whole "screen", which here is the stage.
    private func applyWidth() {
        guard hasTheme, bounds.width > 0 else { return }
        let available = max(OverlayLayout.minWidth, bounds.width - 24)
        let width: CGFloat
        let scale: CGFloat
        if theme.backgroundStyle == .bar {
            width = bounds.width
            scale = 1
        } else {
            // Measure against the real `overlayWidth`, not the stage, so the
            // pill truncates only where the overlay itself would.
            width = OverlayLayout.trackWidth(
                lineTexts: LyricPreviewSample.lines, secondaryTexts: [],
                currentFont: theme.currentLineFont, nextFont: theme.nextLineFont,
                letterSpacing: theme.letterSpacing,
                maxWidth: theme.overlayWidth)
            scale = LyricPreviewFit.scale(desiredWidth: width, availableWidth: available)
        }
        let transform: CGAffineTransform = scale < 1
            ? CGAffineTransform(scaleX: scale, y: scale) : .identity
        if pill.layer?.affineTransform() != transform {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pill.layer?.setAffineTransform(transform)
            CATransaction.commit()
        }
        guard abs(pillWidth.constant - width) > 0.5 else { return }
        pillWidth.constant = width
    }

    private func applyBackground() {
        backgroundEffect?.removeFromSuperview()
        backgroundEffect = nil
        backgroundFill?.removeFromSuperview()
        backgroundFill = nil

        func pin(_ view: NSView) {
            view.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(view, positioned: .below, relativeTo: currentA)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
                view.topAnchor.constraint(equalTo: pill.topAnchor),
                view.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
            ])
        }

        switch theme.backgroundStyle {
        case .none:
            break

        case .frostedPill, .bar:
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            // The overlay blurs the desktop behind it; here the stage's own
            // backdrop plays that part, so the blur must stay inside the window.
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.alphaValue = theme.backgroundOpacity
            effect.wantsLayer = true
            effect.layer?.cornerRadius = theme.backgroundStyle == .bar ? 0 : theme.backgroundCornerRadius
            effect.layer?.masksToBounds = true
            pin(effect)
            backgroundEffect = effect

        case .solidPill:
            let fill = NSView()
            fill.wantsLayer = true
            fill.layer?.backgroundColor = theme.backgroundColor.cgColor
            fill.layer?.cornerRadius = theme.backgroundCornerRadius
            fill.alphaValue = theme.backgroundOpacity
            pin(fill)
            backgroundFill = fill
        }
    }

    // MARK: Karaoke fill

    private func applyKaraoke() {
        guard theme.karaokeFillEnabled else {
            currentA.layer?.mask = nil
            currentB.layer?.mask = nil
            maskA = nil
            maskB = nil
            return
        }
        layoutSubtreeIfNeeded()
        if maskA == nil {
            let mask = Self.makeMask()
            currentA.layer?.mask = mask
            maskA = mask
        }
        if maskB == nil {
            let mask = Self.makeMask()
            currentB.layer?.mask = mask
            maskB = mask
        }
        syncMasks()
        if !isDemoRunning { setFill(LyricPreviewFill.restProgress, animated: false) }
    }

    private static func makeMask() -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.colors = [NSColor.white.cgColor, NSColor.white.cgColor,
                           NSColor.white.withAlphaComponent(0.35).cgColor,
                           NSColor.white.withAlphaComponent(0.35).cgColor]
        gradient.locations = [0, 0, 0.001, 1]
        return gradient
    }

    /// Align each mask with its label's text, not the whole label, so the sweep
    /// starts at the first glyph instead of in the empty space beside it.
    private func syncMasks() {
        guard hasTheme else { return }
        for (mask, label) in [(maskA, currentA), (maskB, currentB)] {
            guard let mask else { continue }
            let textWidth = OverlayLayout.requiredLabelWidth(
                for: label.stringValue, font: theme.currentLineFont, letterSpacing: theme.letterSpacing)
            let target = OverlayLayout.karaokeMaskFrame(labelBounds: label.bounds, textWidth: textWidth)
            guard mask.frame != target else { continue }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.frame = target
            CATransaction.commit()
        }
    }

    private func setFill(_ progress: Double, animated: Bool, duration: TimeInterval = 0) {
        let active = useA ? currentA : currentB
        guard let mask = active.layer?.mask as? CAGradientLayer else { return }
        syncMasks()
        let stops = LyricPreviewFill.locations(progress: progress, edgeWidth: theme.fillEdgeWidth)
            .map { NSNumber(value: Double($0)) }

        mask.removeAnimation(forKey: "karaokeFill")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.locations = stops
        CATransaction.commit()

        guard animated, duration > 0 else { return }
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = LyricPreviewFill.locations(progress: 0, edgeWidth: theme.fillEdgeWidth)
            .map { NSNumber(value: Double($0)) }
        anim.toValue = stops
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        mask.add(anim, forKey: "karaokeFill")
    }

    // MARK: Demo

    private var cycleInterval: TimeInterval { max(1.5, theme.animationDuration + 1.1) }

    private func startDemo() {
        demoTimer?.invalidate()
        demoStepsLeft = demoSteps
        step()
        demoTimer = Timer.scheduledTimer(withTimeInterval: cycleInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.demoStepsLeft <= 0 {
                self.stopDemo()
                self.settle()
            } else {
                self.step()
            }
        }
    }

    private func stopDemo() {
        demoTimer?.invalidate()
        demoTimer = nil
        demoStepsLeft = 0
    }

    /// Return the stage to its resting state: the current line visible, its
    /// partner hidden, the fill frozen where the soft edge can be judged.
    private func settle() {
        stopDemo()
        let active = useA ? currentA : currentB
        let hidden = useA ? currentB : currentA
        let activeTop = useA ? currentTopA! : currentTopB!
        let hiddenTop = useA ? currentTopB! : currentTopA!

        active.layer?.removeAllAnimations()
        hidden.layer?.removeAllAnimations()
        active.alphaValue = 1
        active.layer?.setAffineTransform(.identity)
        hidden.alphaValue = 0
        hidden.layer?.setAffineTransform(.identity)
        activeTop.constant = metrics.currentTop
        hiddenTop.constant = metrics.currentTop
        layoutSubtreeIfNeeded()
        syncMasks()
        if theme.karaokeFillEnabled { setFill(LyricPreviewFill.restProgress, animated: false) }
    }

    private func step() {
        demoStepsLeft -= 1
        lineIndex = LyricPreviewSample.advance(lineIndex)
        let incomingText = LyricPreviewSample.line(at: lineIndex)
        let followingText = LyricPreviewSample.line(at: LyricPreviewSample.advance(lineIndex))

        let outgoing = useA ? currentA : currentB
        let incoming = useA ? currentB : currentA
        let outgoingTop = useA ? currentTopA! : currentTopB!
        let incomingTop = useA ? currentTopB! : currentTopA!
        let rest = metrics.currentTop

        // Hide the recycled label before rewriting it, with implicit animations
        // suppressed and flushed: CoreAnimation builds the next animation from
        // the *presentation* value, so a plain assignment is smoothed over and
        // the text swap stays visible mid-fade.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        incoming.layer?.removeAllAnimations()
        incoming.alphaValue = 0
        CATransaction.commit()
        CATransaction.flush()

        incoming.attributedStringValue = OverlayLayout.attributedText(
            incomingText, font: theme.currentLineFont, letterSpacing: theme.letterSpacing)
        layoutSubtreeIfNeeded()
        syncMasks()

        useA.toggle()
        if theme.karaokeFillEnabled {
            setFill(1.0, animated: true, duration: cycleInterval)
        }

        let duration = theme.animationDuration

        switch theme.transitionStyle {
        case .none:
            outgoing.alphaValue = 0
            outgoingTop.constant = rest
            incoming.alphaValue = 1
            incoming.layer?.setAffineTransform(.identity)
            incomingTop.constant = rest
            layoutSubtreeIfNeeded()

        case .crossfade:
            incomingTop.constant = rest
            outgoingTop.constant = rest
            layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                outgoing.animator().alphaValue = 0
                incoming.animator().alphaValue = 1
            }

        case .slideUp:
            incomingTop.constant = rest + slideDistance
            layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                outgoingTop.constant = rest - slideDistance
                outgoing.animator().alphaValue = 0
                incomingTop.constant = rest
                incoming.animator().alphaValue = 1
                layoutSubtreeIfNeeded()
            }

        case .scaleFade:
            incomingTop.constant = rest
            outgoingTop.constant = rest
            layoutSubtreeIfNeeded()
            incoming.layer?.setAffineTransform(CGAffineTransform(scaleX: 1.15, y: 1.15))
            // Layer transforms belong to CATransaction; the alpha below rides the
            // AppKit animator. The two run side by side, as in the overlay.
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            CATransaction.setCompletionBlock { outgoing.layer?.setAffineTransform(.identity) }
            outgoing.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.75, y: 0.75))
            incoming.layer?.setAffineTransform(.identity)
            CATransaction.commit()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                outgoing.animator().alphaValue = 0
                incoming.animator().alphaValue = 1
            }

        case .push:
            incomingTop.constant = rest + slideDistance * 2
            layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                outgoingTop.constant = rest - slideDistance * 2
                outgoing.animator().alphaValue = 0
                incomingTop.constant = rest
                incoming.animator().alphaValue = 1
                layoutSubtreeIfNeeded()
            }
        }

        // The second line follows a beat later, the way it does during playback.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            secondLabel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.secondLabel.attributedStringValue = OverlayLayout.attributedText(
                followingText, font: self.theme.nextLineFont, letterSpacing: self.theme.letterSpacing)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.secondLabel.animator().alphaValue = self.theme.nextLineOpacity
            }
        }
    }
}

// MARK: - SwiftUI

private struct LyricPreviewRepresentable: NSViewRepresentable {
    let theme: Theme
    let replayToken: Int

    func makeNSView(context: Context) -> LyricPreviewStage {
        let stage = LyricPreviewStage()
        stage.update(theme: theme, replayToken: replayToken)
        return stage
    }

    func updateNSView(_ stage: LyricPreviewStage, context: Context) {
        stage.update(theme: theme, replayToken: replayToken)
    }
}

/// The preview panel pinned above the Appearance controls.
struct LyricPreviewPanel: View {
    let theme: Theme
    @State private var replayToken = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LyricPreviewRepresentable(theme: theme, replayToken: replayToken)
            Button {
                replayToken += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(5)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("Play the transition again")
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
