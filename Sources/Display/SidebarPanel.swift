import AppKit

class SidebarPanel: NSWindow {
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private var lineLabels: [NSTextField] = []
    private var currentIndex: Int = -1

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 300
        let height = screen.visibleFrame.height
        let x = screen.visibleFrame.maxX - width
        let y = screen.visibleFrame.origin.y

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = true

        setupContent()
    }

    private func setupContent() {
        let effectView = NSVisualEffectView(frame: contentView!.bounds)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .sidebar
        effectView.blendingMode = .behindWindow
        effectView.state = .active

        // Title bar area
        let titleLabel = NSTextField(labelWithString: "LyricSync")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let clipView = NSClipView()
        clipView.drawsBackground = false

        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -16),
        ])

        scrollView.documentView = documentView
        effectView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        contentView = effectView
    }

    func updateLyrics(lines: [LyricLine], currentIndex: Int) {
        // Rebuild labels if line count changed
        if lineLabels.count != lines.count {
            lineLabels.forEach { $0.removeFromSuperview() }
            stackView.arrangedSubviews.forEach { stackView.removeArrangedSubview($0) }
            lineLabels.removeAll()

            for line in lines {
                let label = NSTextField(labelWithString: line.text)
                label.font = NSFont.systemFont(ofSize: 14)
                label.textColor = .secondaryLabelColor
                label.maximumNumberOfLines = 0
                label.lineBreakMode = .byWordWrapping
                label.isBezeled = false
                label.drawsBackground = false
                label.isEditable = false
                label.isSelectable = false
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                lineLabels.append(label)
                stackView.addArrangedSubview(label)
            }
        }

        self.currentIndex = currentIndex

        // Update highlighting
        for (i, label) in lineLabels.enumerated() {
            if i == currentIndex {
                label.font = NSFont.systemFont(ofSize: 16, weight: .bold)
                label.textColor = .white
            } else {
                label.font = NSFont.systemFont(ofSize: 14)
                label.textColor = .secondaryLabelColor
            }
        }

        // Scroll to current line
        if currentIndex >= 0 && currentIndex < lineLabels.count {
            let label = lineLabels[currentIndex]
            let labelFrame = label.convert(label.bounds, to: scrollView.documentView)
            let visibleHeight = scrollView.contentView.bounds.height
            let targetY = labelFrame.midY - visibleHeight / 2

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                scrollView.contentView.animator().setBoundsOrigin(
                    NSPoint(x: 0, y: max(0, targetY))
                )
            }
        }
    }
}
