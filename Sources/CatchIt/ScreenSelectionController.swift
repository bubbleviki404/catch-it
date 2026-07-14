import AppKit

final class ScreenSelectionController {
    enum Result {
        case selected(screen: NSScreen, rect: CGRect)
        case cancelled
    }

    private var windows: [NSWindow] = []
    private var completion: ((Result) -> Void)?
    private var isFinished = false
    private var keyMonitor: Any?

    func begin(completion: @escaping (Result) -> Void) {
        self.completion = completion
        isFinished = false

        windows = NSScreen.screens.map { screen in
            let selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            let window = SelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.setFrame(screen.frame, display: false)
            window.contentView = selectionView
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = true
            window.acceptsMouseMovedEvents = true
            window.ignoresMouseEvents = false

            selectionView.onSelection = { [weak self] rect in
                self?.finish(.selected(screen: screen, rect: rect))
            }
            selectionView.onCancel = { [weak self] in self?.finish(.cancelled) }
            window.orderFrontRegardless()
            return window
        }
        // A non-activating panel can become key without making CatchIt the
        // active application. This preserves the source app's menu bar while
        // still allowing Esc and Space to work reliably.
        let mouseLocation = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(mouseLocation) } ?? windows.first)?.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.finish(.cancelled)
                return nil
            }
            if event.keyCode == 49 {
                let mouse = NSEvent.mouseLocation
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
                    self.finish(.selected(screen: screen, rect: CGRect(origin: .zero, size: screen.frame.size)))
                    return nil
                }
            }
            return event
        }
    }

    private func finish(_ result: Result) {
        guard !isFinished else { return }
        isFinished = true
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        completion?(result)
        completion = nil
    }
}

/// A key-capable overlay that does not activate CatchIt or replace the source
/// application's menu bar. This keeps the pixels being captured unchanged.
final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var trackingAreaRef: NSTrackingArea?

    private lazy var fullScreenButton: NSButton = {
        let button = NSButton(title: "截取此屏幕", target: self, action: #selector(captureFullScreen))
        button.image = NSImage(systemSymbolName: "rectangle.inset.filled", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.toolTip = "截取鼠标所在的整个屏幕（空格）"
        button.setAccessibilityLabel("截取此屏幕")
        button.setAccessibilityHelp("截取当前屏幕，也可以按空格键")
        return button
    }()

    private var fullScreenButtonRect: CGRect {
        CGRect(x: bounds.midX - 74, y: bounds.maxY - 70, width: 148, height: 38)
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(fullScreenButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("截图区域选择")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        fullScreenButton.frame = fullScreenButtonRect
    }

    @objc private func captureFullScreen() {
        onSelection?(bounds)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.36).setFill()
        bounds.fill()

        guard let rect = selectionRect, rect.width > 0, rect.height > 0 else {
            drawHint("拖拽框选区域 · 点击上方按钮截取全屏 · Esc 取消", at: CGPoint(x: bounds.midX, y: bounds.midY))
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        rect.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        let sizeText = "\(Int(rect.width)) × \(Int(rect.height))"
        drawHint(sizeText, at: CGPoint(x: rect.minX + 52, y: max(18, rect.minY - 18)))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if fullScreenButtonRect.contains(point) { return }
        startPoint = point
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width >= 3, rect.height >= 3 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }
        onSelection?(rect.intersection(bounds))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else if event.keyCode == 49 {
            onSelection?(bounds)
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func drawHint(_ string: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = string.size(withAttributes: attributes)
        let background = CGRect(x: point.x - size.width / 2 - 10, y: point.y - size.height / 2 - 6, width: size.width + 20, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: background, xRadius: 7, yRadius: 7).fill()
        string.draw(at: CGPoint(x: background.minX + 10, y: background.minY + 6), withAttributes: attributes)
    }
}
