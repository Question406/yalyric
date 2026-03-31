import AppKit
import QuartzCore

/// A horizontal stack of per-word NSTextField labels, each with its own gradient mask for karaoke fill.
class WordStackView: NSView {
    private(set) var wordLabels: [NSTextField] = []
    private var wordMasks: [CAGradientLayer] = []
    private let stackView = NSStackView()
    private var karaokeFillEnabled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        stackView.orientation = .horizontal
        stackView.spacing = 0
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Rebuild labels for a new set of words.
    func setWords(
        _ words: [String],
        font: NSFont,
        textColor: NSColor,
        letterSpacing: CGFloat,
        shadow: NSShadow?,
        karaokeFillEnabled: Bool
    ) {
        self.karaokeFillEnabled = karaokeFillEnabled

        // Remove old labels
        for label in wordLabels {
            stackView.removeArrangedSubview(label)
            label.removeFromSuperview()
        }
        wordLabels.removeAll()
        wordMasks.removeAll()

        // Create one label per word
        for word in words {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byClipping
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.wantsLayer = true
            label.translatesAutoresizingMaskIntoConstraints = false

            // Build attributed string
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
            ]
            if letterSpacing != 0 {
                attrs[.kern] = letterSpacing
            }
            label.attributedStringValue = NSAttributedString(string: word, attributes: attrs)
            if let shadow = shadow {
                label.shadow = shadow
            }

            stackView.addArrangedSubview(label)
            wordLabels.append(label)

            // Create gradient mask if karaoke fill enabled
            if karaokeFillEnabled {
                let mask = CAGradientLayer()
                mask.startPoint = CGPoint(x: 0, y: 0.5)
                mask.endPoint = CGPoint(x: 1, y: 0.5)
                mask.colors = [
                    NSColor.white.cgColor,
                    NSColor.white.cgColor,
                    NSColor.white.withAlphaComponent(0.35).cgColor,
                    NSColor.white.withAlphaComponent(0.35).cgColor,
                ]
                mask.locations = [0, 0, 0.001, 1]
                label.layer?.mask = mask
                wordMasks.append(mask)
            }
        }
    }

    /// Sync gradient mask frames to label bounds. Call after layout changes.
    func syncMaskFrames() {
        for (i, label) in wordLabels.enumerated() where i < wordMasks.count {
            wordMasks[i].frame = label.bounds
        }
    }

    /// Update per-word karaoke fill progress.
    func updateProgresses(_ progresses: [Double], fillEdgeWidth: CGFloat, animated: Bool) {
        guard karaokeFillEnabled else { return }

        // Ensure layout is current
        layoutSubtreeIfNeeded()
        syncMaskFrames()

        for (i, mask) in wordMasks.enumerated() {
            let p = Float(i < progresses.count ? min(1, max(0, progresses[i])) : 0)
            let edge = Float(fillEdgeWidth)
            let newLocations: [NSNumber] = [0, NSNumber(value: p), NSNumber(value: p + edge), 1]

            if animated {
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
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                mask.locations = newLocations
                CATransaction.commit()
            }
        }
    }

    /// Reset all word masks to unfilled state.
    func resetMasks(fillEdgeWidth: CGFloat) {
        for mask in wordMasks {
            mask.removeAnimation(forKey: "karaokeFill")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.locations = [0, 0, NSNumber(value: Float(fillEdgeWidth)), 1]
            CATransaction.commit()
        }
    }

    /// Remove all gradient masks.
    func clearMasks() {
        for label in wordLabels {
            label.layer?.mask = nil
        }
        wordMasks.removeAll()
    }

    /// Total width of all word labels — for dynamic sizing.
    var intrinsicTextWidth: CGFloat {
        wordLabels.reduce(0) { sum, label in
            sum + label.intrinsicContentSize.width
        }
    }
}
