import AppKit

/// A brief, non-activating confirmation that remains visible even when the
/// menu-bar status item is hidden by the system or a menu-bar manager.
final class FeedbackPresenter {
    enum Style {
        case success
        case error
        case info

        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: NSColor {
            switch self {
            case .success: return .systemGreen
            case .error: return .systemRed
            case .info: return .systemBlue
            }
        }
    }

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func show(_ message: String, style: Style = .success) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.show(message, style: style) }
            return
        }

        dismissWorkItem?.cancel()
        panel?.orderOut(nil)
        panel?.close()

        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let width = min(max(textWidth + 72, 176), 360)
        let height: CGFloat = 50
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let frame = NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.maxY - height - 22,
            width: width,
            height: height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.alphaValue = 0

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 13
        background.layer?.masksToBounds = true
        panel.contentView = background

        let symbol = NSImageView()
        symbol.image = NSImage(
            systemSymbolName: style.symbol,
            accessibilityDescription: style == .success ? "成功" : message
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        symbol.contentTintColor = style.color
        symbol.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [symbol, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            symbol.widthAnchor.constraint(equalToConstant: 22),
            symbol.heightAnchor.constraint(equalToConstant: 22),
            row.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: background.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -16)
        ])

        self.panel = panel
        panel.orderFrontRegardless()
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSNumber(value: NSAccessibilityPriorityLevel.high.rawValue)
            ]
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak panel] in
                guard let self, let panel, self.panel === panel else { return }
                panel.orderOut(nil)
                panel.close()
                self.panel = nil
            })
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: workItem)
    }
}
