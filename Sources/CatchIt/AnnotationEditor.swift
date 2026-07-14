import AppKit

private enum AnnotationTool: Int {
    case select = 0
    case rectangle = 1
    case mosaic = 2
    case note = 3
    case text = 4
    case crop = 5
}

private enum AnnotationKind {
    case rectangle
    case mosaic
    case note
    case text
    case crop
}

private struct Annotation {
    var kind: AnnotationKind
    var rect: CGRect
    var text: String = ""
    var color: NSColor
}

private enum ResizeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

final class AnnotationEditorWindowController: NSWindowController, NSWindowDelegate {
    private static let palette: [NSColor] = [
        .systemPurple, .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemTeal, .systemGray
    ]
    private static let paletteNames = ["紫色", "红色", "橙色", "黄色", "绿色", "青色", "灰色"]

    private let store: ScreenshotStore
    private let onFinish: (String) -> Void
    private let canvas: AnnotationCanvasView
    private var didFinish = false
    private var isSaving = false
    private var toolPicker: NSSegmentedControl!
    private var colorButtons: [ColorSwatchButton] = []
    private var colorStack: NSStackView!
    private var contextHint: NSTextField!

    init(image: NSImage, store: ScreenshotStore, onFinish: @escaping (String) -> Void) {
        self.store = store
        self.onFinish = onFinish
        self.canvas = AnnotationCanvasView(image: image)

        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(1180, visible.width * 0.9)
        let height = min(820, visible.height * 0.88)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CatchIt 标注"
        window.minSize = NSSize(width: 820, height: 520)
        window.center()
        super.init(window: window)
        window.delegate = self
        buildInterface(in: window)

        canvas.onToolChanged = { [weak self] tool in
            guard let self else { return }
            self.toolPicker.selectedSegment = tool.rawValue
            if tool != .select {
                self.updateToolPresentation(tool)
            } else if self.colorStack.isHidden {
                self.contextHint.stringValue = self.hint(for: .select)
            }
        }
        canvas.onSelectionColorChanged = { [weak self] color in
            guard let self,
                  let index = Self.palette.firstIndex(where: { $0.isEqual(color) }) else { return }
            self.selectColorButton(at: index)
        }
        canvas.onColorAvailabilityChanged = { [weak self] isAvailable in
            self?.setColorsEnabled(isAvailable)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildInterface(in window: NSWindow) {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = root

        let toolbar = NSVisualEffectView()
        toolbar.material = .headerView
        toolbar.blendingMode = .withinWindow
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        canvas.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar)
        root.addSubview(canvas)

        toolPicker = NSSegmentedControl(
            labels: ["选择", "矩形", "马赛克", "便签", "文字", "裁剪"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(toolChanged(_:))
        )
        toolPicker.selectedSegment = AnnotationTool.rectangle.rawValue
        let toolSymbols: [String?] = ["cursorarrow", "rectangle", "square.grid.3x3.fill", "note.text", nil, "crop"]
        for (index, symbol) in toolSymbols.enumerated() {
            guard let symbol else { continue }
            toolPicker.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), forSegment: index)
        }
        let toolTips = ["选择、移动和缩放", "矩形重点框", "马赛克", "便签", "文字", "裁剪输出"]
        for index in toolTips.indices { toolPicker.setToolTip(toolTips[index], forSegment: index) }
        toolPicker.setAccessibilityLabel("标注工具")

        let colors = NSStackView()
        colors.orientation = .horizontal
        colors.alignment = .centerY
        colors.spacing = 7
        colors.setAccessibilityLabel("常用颜色")
        colorStack = colors
        for index in Self.palette.indices {
            let button = ColorSwatchButton(color: Self.palette[index], name: Self.paletteNames[index])
            button.tag = index
            button.target = self
            button.action = #selector(colorChanged(_:))
            colorButtons.append(button)
            colors.addArrangedSubview(button)
        }
        selectColorButton(at: 1)

        contextHint = NSTextField(labelWithString: "")
        contextHint.font = .systemFont(ofSize: 12, weight: .medium)
        contextHint.textColor = .secondaryLabelColor
        contextHint.lineBreakMode = .byTruncatingTail
        contextHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contextHint.isHidden = true

        let undoButton = NSButton(title: "撤销", target: self, action: #selector(undo))
        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        undoButton.imagePosition = .imageLeading
        undoButton.keyEquivalent = "z"
        undoButton.keyEquivalentModifierMask = .command
        undoButton.toolTip = "撤销上一步（⌘Z）"

        let redoButton = NSButton(title: "重做", target: self, action: #selector(redo))
        redoButton.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: nil)
        redoButton.imagePosition = .imageLeading
        redoButton.keyEquivalent = "z"
        redoButton.keyEquivalentModifierMask = [.command, .shift]
        redoButton.toolTip = "重做上一步（⌘⇧Z）"

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        let saveButton = NSButton(title: "完成", target: self, action: #selector(save))
        saveButton.isBordered = false
        saveButton.wantsLayer = true
        saveButton.layer?.cornerRadius = 8
        saveButton.layer?.backgroundColor = NSColor.systemGreen.blended(withFraction: 0.30, of: .black)?.cgColor
        saveButton.contentTintColor = .white
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.widthAnchor.constraint(equalToConstant: 66).isActive = true
        saveButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command
        saveButton.toolTip = "保存到今日目录并复制到剪贴板（⌘S）"

        let stack = NSStackView(views: [
            toolPicker, makeDivider(), colors, contextHint, makeDivider(), undoButton, redoButton, NSView(), cancelButton, saveButton
        ])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 62),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        let tool = AnnotationTool(rawValue: sender.selectedSegment) ?? .rectangle
        canvas.tool = tool
        updateToolPresentation(tool)
    }

    @objc private func colorChanged(_ sender: ColorSwatchButton) {
        guard Self.palette.indices.contains(sender.tag) else { return }
        selectColorButton(at: sender.tag)
        canvas.applyColor(Self.palette[sender.tag])
    }

    private func selectColorButton(at index: Int) {
        for (buttonIndex, button) in colorButtons.enumerated() {
            button.isSwatchSelected = buttonIndex == index
        }
    }

    private func setColorsEnabled(_ enabled: Bool) {
        colorStack?.isHidden = !enabled
        contextHint?.isHidden = enabled
        if !enabled {
            let tool = AnnotationTool(rawValue: toolPicker.selectedSegment) ?? .select
            contextHint.stringValue = hint(for: tool)
        }
        colorButtons.forEach {
            $0.isEnabled = enabled
            $0.alphaValue = 1
        }
    }

    private func updateToolPresentation(_ tool: AnnotationTool) {
        let showsColors = tool == .rectangle || tool == .note || tool == .text
        setColorsEnabled(showsColors)
        if !showsColors { contextHint.stringValue = hint(for: tool) }
    }

    private func hint(for tool: AnnotationTool) -> String {
        switch tool {
        case .select: return "选择标注，拖动圆点缩放"
        case .mosaic: return "拖动覆盖敏感内容"
        case .crop: return "拖出范围，切换工具后应用"
        case .rectangle, .note, .text: return ""
        }
    }

    private func makeDivider() -> NSView {
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return divider
    }

    @objc private func undo() { canvas.undo() }
    @objc private func redo() { canvas.redo() }
    @objc private func cancel() { window?.close() }

    @objc private func save() {
        guard !isSaving else { return }
        isSaving = true

        // Hide on the current event cycle so the click feels immediate. The
        // AppKit annotation render happens on the next cycle; compression and
        // disk I/O then continue on ScreenshotStore's image queue.
        window?.orderOut(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let rendered = canvas.renderedImage()
            store.saveAsync(rendered, suffix: "marked") { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    didFinish = true
                    onFinish("已保存并复制")
                    window?.close()
                case .failure(let error):
                    isSaving = false
                    didFinish = false
                    window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert(error: error)
                    alert.messageText = "保存失败，标注仍然保留"
                    alert.informativeText = "请检查保存目录权限或磁盘空间，然后再次点击“完成”。\n\n\(error.localizedDescription)"
                    if let window { alert.beginSheetModal(for: window) }
                }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if !didFinish { onFinish("") }
    }

    func windowDidResignKey(_ notification: Notification) {
        canvas.commitCropIfNeeded()
    }
}

private final class ColorSwatchButton: NSButton {
    let swatchColor: NSColor
    var isSwatchSelected = false { didSet { needsDisplay = true } }

    init(color: NSColor, name: String) {
        self.swatchColor = color
        super.init(frame: CGRect(x: 0, y: 0, width: 29, height: 29))
        title = ""
        isBordered = false
        bezelStyle = .shadowlessSquare
        toolTip = name
        setAccessibilityLabel(name)
        setAccessibilityRole(.radioButton)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 29),
            heightAnchor.constraint(equalToConstant: 29)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        if isSwatchSelected {
            NSColor.labelColor.withAlphaComponent(0.16).setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        }

        let circle = bounds.insetBy(dx: isSwatchSelected ? 5 : 4, dy: isSwatchSelected ? 5 : 4)
        swatchColor.setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.separatorColor.setStroke()
        let outline = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = isSwatchSelected ? 1.5 : 1
        outline.stroke()
    }
}

private final class AnnotationCanvasView: NSView, NSTextViewDelegate {
    let image: NSImage
    var onToolChanged: ((AnnotationTool) -> Void)?
    var onSelectionColorChanged: ((NSColor) -> Void)?
    var onColorAvailabilityChanged: ((Bool) -> Void)?

    var tool: AnnotationTool = .rectangle {
        didSet {
            if oldValue != tool { finishInlineEditing(removeIfEmpty: true) }
            if tool == .crop, let cropIndex = annotations.lastIndex(where: { $0.kind == .crop }) {
                setSelection(cropIndex)
            } else if oldValue == .crop,
                      tool != .crop,
                      let selectedIndex,
                      annotations.indices.contains(selectedIndex),
                      annotations[selectedIndex].kind == .crop {
                setSelection(nil)
            }
            switch tool {
            case .note: currentColor = .systemYellow
            case .rectangle, .text: currentColor = .systemRed
            case .select, .mosaic, .crop: break
            }
            if tool == .rectangle || tool == .note || tool == .text {
                onSelectionColorChanged?(currentColor)
                onColorAvailabilityChanged?(true)
            } else if tool == .select,
                      let selectedIndex,
                      annotations.indices.contains(selectedIndex) {
                let annotation = annotations[selectedIndex]
                let supportsColor = annotation.kind == .rectangle || annotation.kind == .note || annotation.kind == .text
                onColorAvailabilityChanged?(supportsColor)
                if supportsColor { onSelectionColorChanged?(annotation.color) }
            } else {
                onColorAvailabilityChanged?(false)
            }
            updateInlineEditorFrame()
            needsDisplay = true
        }
    }

    private var currentColor: NSColor = .systemRed
    private var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var editingSnapshot: [Annotation]?
    private var selectedIndex: Int?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var movingIndex: Int?
    private var movingOffset: CGPoint = .zero
    private var resizeHandle: ResizeHandle?
    private var resizeOriginalRect: CGRect?
    private var inlineEditor: InlineAnnotationTextView?
    private var editingIndex: Int?
    private var isFinishingEditing = false
    private lazy var pixelatedImage: NSImage = makePixelatedImage()
    private let fullViewport = CGRect(x: 0, y: 0, width: 1, height: 1)

    private var committedCrop: CGRect? {
        annotations.last(where: { $0.kind == .crop })?.rect
    }

    private var activeViewport: CGRect {
        tool == .crop ? fullViewport : (committedCrop ?? fullViewport)
    }

    override var acceptsFirstResponder: Bool { true }

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("截图标注画布")
        setAccessibilityHelp("按 Tab 在标注之间切换，方向键移动，Delete 删除，回车编辑文字或确认裁剪")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func runCropViewportSelfTest() -> AnnotationCropSelfTestResult {
        let testImage = NSImage(size: NSSize(width: 1000, height: 800))
        testImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 800).fill()
        testImage.unlockFocus()

        let canvas = AnnotationCanvasView(image: testImage)
        canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        canvas.annotations.append(Annotation(
            kind: .crop,
            rect: CGRect(x: 0.2, y: 0.1, width: 0.4, height: 0.6),
            color: .clear
        ))
        canvas.tool = .crop
        let focusedAspect = canvas.imageRect.width / canvas.imageRect.height
        canvas.commitCropIfNeeded()
        let committedAspect = canvas.imageRect.width / canvas.imageRect.height
        let rendered = canvas.renderedImage()
        let mosaicCacheSize = canvas.pixelatedImage.size
        return AnnotationCropSelfTestResult(
            focusedAspect: focusedAspect,
            committedAspect: committedAspect,
            outputSize: rendered.size,
            didLeaveCropTool: canvas.tool == .select,
            mosaicCacheSize: mosaicCacheSize
        )
    }

    static func runHistorySelfTest() -> AnnotationHistorySelfTestResult {
        let canvas = AnnotationCanvasView(image: NSImage(size: NSSize(width: 800, height: 600)))
        canvas.annotations.append(Annotation(
            kind: .rectangle,
            rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            color: .systemRed
        ))
        canvas.recordHistory()
        canvas.annotations.append(Annotation(
            kind: .note,
            rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            text: "测试",
            color: .systemYellow
        ))
        let countAfterEdit = canvas.annotations.count
        canvas.undo()
        let countAfterUndo = canvas.annotations.count
        canvas.redo()
        return AnnotationHistorySelfTestResult(
            countAfterEdit: countAfterEdit,
            countAfterUndo: countAfterUndo,
            countAfterRedo: canvas.annotations.count
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        bounds.fill()
        let sourceRect = denormalize(activeViewport, in: CGRect(origin: .zero, size: image.size))
        image.draw(
            in: imageRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: imageRect).addClip()
        for (index, annotation) in annotations.enumerated() where annotation.kind != .crop {
            if index == editingIndex, annotation.kind != .rectangle {
                draw(annotation, in: imageRect, viewport: activeViewport, hideText: true)
            } else {
                draw(annotation, in: imageRect, viewport: activeViewport)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        if tool == .crop,
           let crop = annotations.last(where: { $0.kind == .crop }),
           dragStart == nil {
            drawCropOverlay(crop.rect)
        }

        if let start = dragStart, let current = dragCurrent {
            let rect = normalizedRect(from: start, to: current)
            switch tool {
            case .rectangle:
                draw(Annotation(kind: .rectangle, rect: rect, color: currentColor), in: imageRect, viewport: activeViewport)
            case .mosaic:
                draw(Annotation(kind: .mosaic, rect: rect, color: .clear), in: imageRect, viewport: activeViewport)
            case .crop:
                drawCropOverlay(rect)
            case .select, .note, .text:
                break
            }
        }
        if let selectedIndex,
           annotations.indices.contains(selectedIndex),
           annotations[selectedIndex].kind != .crop || tool == .crop {
            drawSelection(for: annotations[selectedIndex])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(viewPoint) else {
            finishInlineEditing(removeIfEmpty: true)
            if tool == .crop, committedCrop != nil {
                commitCropIfNeeded()
            } else {
                setSelection(nil)
            }
            return
        }
        let point = normalize(viewPoint)

        if let selectedIndex,
           annotations.indices.contains(selectedIndex),
           let handle = hitResizeHandle(at: viewPoint, annotation: annotations[selectedIndex]) {
            finishInlineEditing(removeIfEmpty: false)
            recordHistory()
            resizeHandle = handle
            resizeOriginalRect = annotations[selectedIndex].rect
            window?.makeFirstResponder(self)
            return
        }

        if event.clickCount >= 2, let hit = hitTestAnnotation(at: point) {
            setSelection(hit)
            tool = .select
            onToolChanged?(.select)
            window?.makeFirstResponder(self)
            if annotations[hit].kind == .note || annotations[hit].kind == .text {
                beginInlineEditing(index: hit)
            }
            return
        }

        if tool == .rectangle,
           let hit = hitTestAnnotation(at: point),
           annotations[hit].kind == .rectangle {
            setSelection(hit)
            tool = .select
            onToolChanged?(.select)
            let rect = annotations[hit].rect
            recordHistory()
            movingIndex = hit
            movingOffset = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
            window?.makeFirstResponder(self)
            return
        }

        switch tool {
        case .rectangle, .mosaic, .crop:
            finishInlineEditing(removeIfEmpty: true)
            setSelection(nil)
            dragStart = point
            dragCurrent = point
            window?.makeFirstResponder(self)
        case .note:
            createTextAnnotation(kind: .note, at: point)
        case .text:
            createTextAnnotation(kind: .text, at: point)
        case .select:
            finishInlineEditing(removeIfEmpty: true)
            guard let hit = hitTestAnnotation(at: point) else {
                setSelection(nil)
                window?.makeFirstResponder(self)
                return
            }
            setSelection(hit)
            recordHistory()
            movingIndex = hit
            let rect = annotations[hit].rect
            movingOffset = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
            window?.makeFirstResponder(self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = normalize(clampToImage(convert(event.locationInWindow, from: nil)))
        if (tool == .rectangle || tool == .mosaic || tool == .crop), dragStart != nil {
            dragCurrent = point
            needsDisplay = true
        } else if let selectedIndex,
                  let resizeHandle,
                  let original = resizeOriginalRect {
            resizeAnnotation(at: selectedIndex, from: original, handle: resizeHandle, to: point)
        } else if tool == .select, let index = movingIndex {
            moveAnnotation(at: index, origin: CGPoint(x: point.x - movingOffset.x, y: point.y - movingOffset.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let start = dragStart, let current = dragCurrent {
            let rect = normalizedRect(from: start, to: current)
            let viewport = activeViewport
            if rect.width > viewport.width * 0.008,
               rect.height > viewport.height * 0.008 {
                switch tool {
                case .rectangle:
                    recordHistory()
                    annotations.append(Annotation(kind: .rectangle, rect: rect, color: currentColor))
                case .mosaic:
                    recordHistory()
                    annotations.append(Annotation(kind: .mosaic, rect: rect, color: .clear))
                case .crop:
                    recordHistory()
                    annotations.removeAll { $0.kind == .crop }
                    annotations.append(Annotation(kind: .crop, rect: rect, color: .clear))
                case .select, .note, .text:
                    break
                }
                setSelection(annotations.count - 1)
            }
        }
        dragStart = nil
        dragCurrent = nil
        movingIndex = nil
        resizeHandle = nil
        resizeOriginalRect = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelection()
        } else if event.keyCode == 48 {
            selectNextAnnotation(reverse: event.modifierFlags.contains(.shift))
        } else if [123, 124, 125, 126].contains(event.keyCode), let selectedIndex {
            let step = max(activeViewport.width, activeViewport.height) * (event.modifierFlags.contains(.shift) ? 0.02 : 0.005)
            var origin = annotations[selectedIndex].rect.origin
            switch event.keyCode {
            case 123: origin.x -= step
            case 124: origin.x += step
            case 125: origin.y -= step
            case 126: origin.y += step
            default: break
            }
            recordHistory()
            moveAnnotation(at: selectedIndex, origin: origin)
        } else if event.keyCode == 36 || event.keyCode == 76, tool == .crop, committedCrop != nil {
            commitCropIfNeeded()
        } else if event.keyCode == 36 || event.keyCode == 76,
                  let selectedIndex,
                  annotations[selectedIndex].kind == .note || annotations[selectedIndex].kind == .text {
            beginInlineEditing(index: selectedIndex)
        } else {
            super.keyDown(with: event)
        }
    }

    func commitCropIfNeeded() {
        guard tool == .crop, committedCrop != nil else { return }
        setSelection(nil)
        tool = .select
        onToolChanged?(.select)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func applyColor(_ color: NSColor) {
        currentColor = color
        if let selectedIndex,
           annotations.indices.contains(selectedIndex),
           annotations[selectedIndex].kind != .crop,
           annotations[selectedIndex].kind != .mosaic {
            if !annotations[selectedIndex].color.isEqual(color) { recordHistory() }
            annotations[selectedIndex].color = color
            if let inlineEditor, editingIndex == selectedIndex {
                let annotation = annotations[selectedIndex]
                inlineEditor.textColor = annotation.kind == .note ? noteTextColor : color
                inlineEditor.needsDisplay = true
            }
        }
        needsDisplay = true
    }

    func undo() {
        finishInlineEditing(removeIfEmpty: true)
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        setSelection(nil)
        needsDisplay = true
    }

    func redo() {
        finishInlineEditing(removeIfEmpty: true)
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        setSelection(nil)
        needsDisplay = true
    }

    func clear() {
        finishInlineEditing(removeIfEmpty: true)
        guard !annotations.isEmpty else { return }
        recordHistory()
        annotations.removeAll()
        setSelection(nil)
        needsDisplay = true
    }

    func renderedImage() -> NSImage {
        finishInlineEditing(removeIfEmpty: true)
        let size = image.size
        let fullRect = CGRect(origin: .zero, size: size)
        let crop = annotations.last(where: { $0.kind == .crop })?.rect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let cropRect = denormalize(crop, in: fullRect).integral.intersection(fullRect)
        let result = NSImage(size: cropRect.size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: -cropRect.minX, yBy: -cropRect.minY)
        transform.concat()
        image.draw(in: fullRect, from: .zero, operation: .copy, fraction: 1)
        annotations.filter { $0.kind != .crop }.forEach {
            draw($0, in: fullRect, viewport: fullViewport, outputScale: max(1, size.width / 1200))
        }
        NSGraphicsContext.restoreGraphicsState()
        result.unlockFocus()
        return result
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? NSTextView,
              let editingIndex,
              annotations.indices.contains(editingIndex) else { return }
        annotations[editingIndex].text = editor.string
    }

    private var imageRect: CGRect {
        let inset = bounds.insetBy(dx: 24, dy: 24)
        guard image.size.width > 0, image.size.height > 0 else { return inset }
        let viewport = activeViewport
        let viewportSize = CGSize(
            width: image.size.width * viewport.width,
            height: image.size.height * viewport.height
        )
        let scale = min(inset.width / viewportSize.width, inset.height / viewportSize.height)
        let size = CGSize(width: viewportSize.width * scale, height: viewportSize.height * scale)
        return CGRect(x: inset.midX - size.width / 2, y: inset.midY - size.height / 2, width: size.width, height: size.height)
    }

    private var noteTextColor: NSColor { NSColor(calibratedWhite: 0.12, alpha: 1) }

    private func draw(
        _ annotation: Annotation,
        in target: CGRect,
        viewport: CGRect,
        outputScale: CGFloat = 1,
        hideText: Bool = false
    ) {
        let converted = displayRect(annotation.rect, in: target, viewport: viewport)
        switch annotation.kind {
        case .rectangle:
            annotation.color.setStroke()
            let path = NSBezierPath(roundedRect: converted, xRadius: 5 * outputScale, yRadius: 5 * outputScale)
            path.lineWidth = 4 * outputScale
            path.stroke()
        case .mosaic:
            drawMosaic(annotation, in: converted)
        case .note:
            let fill = annotation.color.blended(withFraction: 0.58, of: .white) ?? annotation.color
            fill.withAlphaComponent(0.97).setFill()
            NSBezierPath(roundedRect: converted, xRadius: 8 * outputScale, yRadius: 8 * outputScale).fill()
            annotation.color.withAlphaComponent(0.45).setStroke()
            let border = NSBezierPath(roundedRect: converted.insetBy(dx: 0.5, dy: 0.5), xRadius: 8 * outputScale, yRadius: 8 * outputScale)
            border.lineWidth = max(1, outputScale)
            border.stroke()
            if !hideText { drawText(annotation, in: converted, outputScale: outputScale, noteStyle: true) }
        case .text:
            if !hideText { drawText(annotation, in: converted, outputScale: outputScale, noteStyle: false) }
        case .crop:
            break
        }
    }

    private func drawMosaic(_ annotation: Annotation, in destination: CGRect) {
        let source = denormalize(annotation.rect, in: CGRect(origin: .zero, size: pixelatedImage.size))
        NSGraphicsContext.current?.imageInterpolation = .none
        pixelatedImage.draw(
            in: destination,
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        NSGraphicsContext.current?.imageInterpolation = .high
    }

    private func drawCropOverlay(_ normalizedCrop: CGRect) {
        let crop = displayRect(normalizedCrop, in: imageRect, viewport: fullViewport)
        let shade = NSBezierPath()
        shade.appendRect(imageRect)
        shade.appendRect(crop)
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.56).setFill()
        shade.fill()

        NSColor.white.withAlphaComponent(0.92).setStroke()
        let border = NSBezierPath(rect: crop)
        border.lineWidth = 1.5
        border.stroke()

        NSColor.white.withAlphaComponent(0.34).setStroke()
        for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
            let vertical = NSBezierPath()
            vertical.move(to: CGPoint(x: crop.minX + crop.width * fraction, y: crop.minY))
            vertical.line(to: CGPoint(x: crop.minX + crop.width * fraction, y: crop.maxY))
            vertical.lineWidth = 1
            vertical.stroke()

            let horizontal = NSBezierPath()
            horizontal.move(to: CGPoint(x: crop.minX, y: crop.minY + crop.height * fraction))
            horizontal.line(to: CGPoint(x: crop.maxX, y: crop.minY + crop.height * fraction))
            horizontal.lineWidth = 1
            horizontal.stroke()
        }
    }

    private func makePixelatedImage() -> NSImage {
        let longestSide = max(image.size.width, image.size.height)
        let block = max(10, longestSide / 150)
        let smallSize = NSSize(
            width: max(1, ceil(image.size.width / block)),
            height: max(1, ceil(image.size.height / block))
        )
        let small = NSImage(size: smallSize)
        small.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .low
        image.draw(in: CGRect(origin: .zero, size: smallSize), from: .zero, operation: .copy, fraction: 1)
        small.unlockFocus()

        // Keep only the tiny source. Drawing it with nearest-neighbour
        // interpolation produces the same mosaic while avoiding a second
        // full-resolution image allocation (about 24 MB on a Retina screen).
        return small
    }

    private func drawText(_ annotation: Annotation, in rect: CGRect, outputScale: CGFloat, noteStyle: Bool) {
        guard !annotation.text.isEmpty else { return }
        let fontSize = noteStyle
            ? max(12 * outputScale, min(28 * outputScale, rect.height * 0.18))
            : max(15 * outputScale, min(72 * outputScale, rect.height * 0.58))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: noteStyle ? .medium : .semibold),
            .foregroundColor: noteStyle ? noteTextColor : annotation.color,
            .paragraphStyle: paragraph
        ]
        let inset = noteStyle ? 12 * outputScale : 4 * outputScale
        annotation.text.draw(in: rect.insetBy(dx: inset, dy: inset * 0.8), withAttributes: attributes)
    }

    private func drawSelection(for annotation: Annotation) {
        let rect = displayRect(annotation.rect, in: imageRect, viewport: activeViewport)
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5)
        outline.lineWidth = 2
        outline.stroke()

        for (_, handleRect) in handleRects(for: annotation) {
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(ovalIn: handleRect).fill()
            NSColor.controlAccentColor.setStroke()
            let handle = NSBezierPath(ovalIn: handleRect.insetBy(dx: 0.5, dy: 0.5))
            handle.lineWidth = 2
            handle.stroke()
        }
    }

    private func createTextAnnotation(kind: AnnotationKind, at point: CGPoint) {
        finishInlineEditing(removeIfEmpty: true)
        recordHistory()
        let viewport = activeViewport
        let width = viewport.width * (kind == .note ? 0.30 : 0.28)
        let height = viewport.height * (kind == .note ? 0.20 : 0.10)
        let origin = CGPoint(
            x: min(max(viewport.minX, point.x), viewport.maxX - width),
            y: min(max(viewport.minY, point.y - height), viewport.maxY - height)
        )
        annotations.append(Annotation(
            kind: kind,
            rect: CGRect(origin: origin, size: CGSize(width: width, height: height)),
            color: currentColor
        ))
        let index = annotations.count - 1
        setSelection(index)
        tool = .select
        onToolChanged?(.select)
        beginInlineEditing(index: index, isNew: true)
    }

    private func beginInlineEditing(index: Int, isNew: Bool = false) {
        finishInlineEditing(removeIfEmpty: true)
        guard annotations.indices.contains(index), annotations[index].kind != .rectangle else { return }
        editingSnapshot = isNew ? nil : annotations
        editingIndex = index
        let annotation = annotations[index]
        let editor = InlineAnnotationTextView(frame: editingFrame(for: annotation))
        editor.delegate = self
        editor.string = annotation.text
        editor.isRichText = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = false
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 4, height: 3)
        editor.textColor = annotation.kind == .note ? noteTextColor : annotation.color
        editor.font = inlineFont(for: annotation)
        editor.placeholder = annotation.kind == .note ? "输入便签…" : "输入文字…"
        editor.onCommit = { [weak self] in
            self?.finishInlineEditing(removeIfEmpty: true)
            self?.window?.makeFirstResponder(self)
        }
        inlineEditor = editor
        addSubview(editor)
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.needsDisplay = true
        needsDisplay = true
    }

    private func finishInlineEditing(removeIfEmpty: Bool) {
        guard !isFinishingEditing else { return }
        isFinishingEditing = true
        defer { isFinishingEditing = false }
        guard let index = editingIndex else { return }
        if let inlineEditor, annotations.indices.contains(index) {
            if let editingSnapshot, annotations[index].text != inlineEditor.string {
                pushUndoSnapshot(editingSnapshot)
            }
            annotations[index].text = inlineEditor.string
        }
        inlineEditor?.delegate = nil
        inlineEditor?.removeFromSuperview()
        inlineEditor = nil
        editingIndex = nil
        editingSnapshot = nil
        if removeIfEmpty,
           annotations.indices.contains(index),
           annotations[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.remove(at: index)
            setSelection(nil)
        }
        needsDisplay = true
    }

    private func inlineFont(for annotation: Annotation) -> NSFont {
        let rect = displayRect(annotation.rect, in: imageRect, viewport: activeViewport)
        let size = annotation.kind == .note
            ? max(12, min(28, rect.height * 0.18))
            : max(15, min(72, rect.height * 0.58))
        return .systemFont(ofSize: size, weight: annotation.kind == .note ? .medium : .semibold)
    }

    private func editingFrame(for annotation: Annotation) -> CGRect {
        let rect = displayRect(annotation.rect, in: imageRect, viewport: activeViewport)
        return annotation.kind == .note ? rect.insetBy(dx: 8, dy: 7) : rect.insetBy(dx: 2, dy: 2)
    }

    private func setSelection(_ index: Int?) {
        selectedIndex = index
        if let index, annotations.indices.contains(index) {
            let annotation = annotations[index]
            let supportsColor = annotation.kind == .rectangle || annotation.kind == .note || annotation.kind == .text
            onColorAvailabilityChanged?(supportsColor)
            if supportsColor { onSelectionColorChanged?(annotation.color) }
        } else {
            onColorAvailabilityChanged?(tool == .rectangle || tool == .note || tool == .text)
        }
        setAccessibilityValue(index.map { "已选择第 \($0 + 1) 个标注，共 \(annotations.count) 个" } ?? "未选择标注，共 \(annotations.count) 个")
        needsDisplay = true
    }

    private func selectNextAnnotation(reverse: Bool) {
        finishInlineEditing(removeIfEmpty: true)
        let selectable = annotations.indices.filter { annotations[$0].kind != .crop || tool == .crop }
        guard !selectable.isEmpty else { setSelection(nil); return }
        guard let selectedIndex, let position = selectable.firstIndex(of: selectedIndex) else {
            setSelection(reverse ? selectable.last : selectable.first)
            return
        }
        let next = reverse
            ? (position - 1 + selectable.count) % selectable.count
            : (position + 1) % selectable.count
        setSelection(selectable[next])
        window?.makeFirstResponder(self)
    }

    private func deleteSelection() {
        finishInlineEditing(removeIfEmpty: false)
        guard let selectedIndex, annotations.indices.contains(selectedIndex) else { return }
        recordHistory()
        annotations.remove(at: selectedIndex)
        setSelection(nil)
    }

    private func hitTestAnnotation(at point: CGPoint) -> Int? {
        let tolerance = max(activeViewport.width, activeViewport.height) * 0.008
        return annotations.indices.reversed().first {
            (annotations[$0].kind != .crop || tool == .crop) &&
            annotations[$0].rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    private func moveAnnotation(at index: Int, origin: CGPoint) {
        guard annotations.indices.contains(index) else { return }
        let old = annotations[index].rect
        let viewport = activeViewport
        let bounded = CGPoint(
            x: min(max(viewport.minX, origin.x), viewport.maxX - old.width),
            y: min(max(viewport.minY, origin.y), viewport.maxY - old.height)
        )
        annotations[index].rect.origin = bounded
        updateInlineEditorFrame()
        needsDisplay = true
    }

    private func resizeAnnotation(at index: Int, from original: CGRect, handle: ResizeHandle, to point: CGPoint) {
        guard annotations.indices.contains(index) else { return }
        var minX = original.minX
        var maxX = original.maxX
        var minY = original.minY
        var maxY = original.maxY

        switch handle {
        case .topLeft: minX = point.x; maxY = point.y
        case .top: maxY = point.y
        case .topRight: maxX = point.x; maxY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; minY = point.y
        case .bottom: minY = point.y
        case .bottomLeft: minX = point.x; minY = point.y
        case .left: minX = point.x
        }

        let viewport = activeViewport
        let minimumWidth = viewport.width * 0.035
        let minimumHeight = viewport.height * 0.035
        if maxX - minX < minimumWidth {
            if handle == .left || handle == .topLeft || handle == .bottomLeft { minX = maxX - minimumWidth }
            else { maxX = minX + minimumWidth }
        }
        if maxY - minY < minimumHeight {
            if handle == .bottom || handle == .bottomLeft || handle == .bottomRight { minY = maxY - minimumHeight }
            else { maxY = minY + minimumHeight }
        }

        minX = max(viewport.minX, minX)
        minY = max(viewport.minY, minY)
        maxX = min(viewport.maxX, maxX)
        maxY = min(viewport.maxY, maxY)
        annotations[index].rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        updateInlineEditorFrame()
        needsDisplay = true
    }

    private func updateInlineEditorFrame() {
        guard let editingIndex,
              annotations.indices.contains(editingIndex),
              let inlineEditor else { return }
        let annotation = annotations[editingIndex]
        inlineEditor.frame = editingFrame(for: annotation)
        inlineEditor.font = inlineFont(for: annotation)
    }

    private func handleRects(for annotation: Annotation) -> [(ResizeHandle, CGRect)] {
        let rect = displayRect(annotation.rect, in: imageRect, viewport: activeViewport)
        let radius: CGFloat = 7
        let points: [(ResizeHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.top, CGPoint(x: rect.midX, y: rect.maxY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY))
        ]
        return points.map { handle, point in
            (handle, CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    private func hitResizeHandle(at point: CGPoint, annotation: Annotation) -> ResizeHandle? {
        handleRects(for: annotation).first { $0.1.insetBy(dx: -4, dy: -4).contains(point) }?.0
    }

    private func normalize(_ point: CGPoint) -> CGPoint {
        let viewport = activeViewport
        return CGPoint(
            x: viewport.minX + ((point.x - imageRect.minX) / imageRect.width) * viewport.width,
            y: viewport.minY + ((point.y - imageRect.minY) / imageRect.height) * viewport.height
        )
    }

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func denormalize(_ rect: CGRect, in target: CGRect) -> CGRect {
        CGRect(
            x: target.minX + rect.minX * target.width,
            y: target.minY + rect.minY * target.height,
            width: rect.width * target.width,
            height: rect.height * target.height
        )
    }

    private func displayRect(_ rect: CGRect, in target: CGRect, viewport: CGRect) -> CGRect {
        guard viewport.width > 0, viewport.height > 0 else { return .zero }
        return CGRect(
            x: target.minX + ((rect.minX - viewport.minX) / viewport.width) * target.width,
            y: target.minY + ((rect.minY - viewport.minY) / viewport.height) * target.height,
            width: (rect.width / viewport.width) * target.width,
            height: (rect.height / viewport.height) * target.height
        )
    }

    private func clampToImage(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(imageRect.minX, point.x), imageRect.maxX),
            y: min(max(imageRect.minY, point.y), imageRect.maxY)
        )
    }

    private func recordHistory() {
        pushUndoSnapshot(annotations)
    }

    private func pushUndoSnapshot(_ snapshot: [Annotation]) {
        undoStack.append(snapshot)
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
        redoStack.removeAll()
    }
}

private final class InlineAnnotationTextView: NSTextView {
    var placeholder = ""
    var onCommit: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        placeholder.draw(at: CGPoint(x: textContainerInset.width + 2, y: textContainerInset.height + 1), withAttributes: attributes)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            onCommit?()
        } else {
            super.keyDown(with: event)
            needsDisplay = true
        }
    }
}

struct AnnotationCropSelfTestResult {
    let focusedAspect: CGFloat
    let committedAspect: CGFloat
    let outputSize: NSSize
    let didLeaveCropTool: Bool
    let mosaicCacheSize: NSSize
}

struct AnnotationHistorySelfTestResult {
    let countAfterEdit: Int
    let countAfterUndo: Int
    let countAfterRedo: Int
}

func runAnnotationCropSelfTest() -> AnnotationCropSelfTestResult {
    AnnotationCanvasView.runCropViewportSelfTest()
}

func runAnnotationHistorySelfTest() -> AnnotationHistorySelfTestResult {
    AnnotationCanvasView.runHistorySelfTest()
}
