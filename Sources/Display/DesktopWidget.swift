import AppKit
import Combine

class DesktopWidget: NSWindow {
    private let stackView = NSStackView()
    private var lineLabels: [NSTextField] = []
    private let visibleLines = 5
    private let currentHighlightIndex = 2
    private var cancellables = Set<AnyCancellable>()

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 400
        let height: CGFloat = 200
        let x = screen.frame.width - width - 40
        let y: CGFloat = 100

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
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
        let container = NSVisualEffectView(frame: contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12

        stackView.orientation = .vertical
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for _ in 0..<visibleLines {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            lineLabels.append(label)
            stackView.addArrangedSubview(label)
        }

        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        contentView = container
    }

    private func applyTheme(_ theme: Theme) {
        for (i, label) in lineLabels.enumerated() {
            if i == currentHighlightIndex {
                label.font = theme.currentLineFont
                label.textColor = theme.textColor
            } else {
                label.font = theme.nextLineFont
                label.textColor = theme.textColor.withAlphaComponent(0.4)
            }
        }
    }

    func updateLyrics(lines: [LyricLine], currentIndex: Int) {
        let theme = ThemeManager.shared.theme
        for i in 0..<visibleLines {
            let lineIndex = currentIndex - currentHighlightIndex + i
            if lineIndex >= 0 && lineIndex < lines.count {
                lineLabels[i].stringValue = lines[lineIndex].text
            } else {
                lineLabels[i].stringValue = ""
            }
            if i == currentHighlightIndex {
                lineLabels[i].font = theme.currentLineFont
                lineLabels[i].textColor = theme.textColor
            } else {
                lineLabels[i].font = theme.nextLineFont
                lineLabels[i].textColor = theme.textColor.withAlphaComponent(0.4)
            }
        }
    }
}
