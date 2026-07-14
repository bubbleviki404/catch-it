import AppKit
import Carbon

enum ShortcutAction: String, Codable, CaseIterable {
    case quickArea
    case quickFullScreen
    case annotateArea
    case annotateFullScreen

    var title: String {
        switch self {
        case .quickArea: return "快速框选"
        case .quickFullScreen: return "快速全屏"
        case .annotateArea: return "框选并标注"
        case .annotateFullScreen: return "全屏并标注"
        }
    }

    var defaultKeyCode: UInt32 {
        switch self {
        case .quickArea: return UInt32(kVK_ANSI_2)
        case .quickFullScreen: return UInt32(kVK_ANSI_1)
        case .annotateArea: return UInt32(kVK_ANSI_E)
        case .annotateFullScreen: return UInt32(kVK_ANSI_F)
        }
    }
}

struct ShortcutDefinition: Codable, Equatable {
    var action: ShortcutAction
    var keyCode: UInt32
    var modifiers: UInt32

    var label: String {
        ShortcutFormatter.label(keyCode: keyCode, modifiers: modifiers)
    }

    static var defaults: [ShortcutDefinition] {
        ShortcutAction.allCases.map {
            ShortcutDefinition(
                action: $0,
                keyCode: $0.defaultKeyCode,
                modifiers: UInt32(controlKey | cmdKey)
            )
        }
    }

    static var deprecatedDefaultSets: [[ShortcutDefinition]] {
        [UInt32(cmdKey | shiftKey), UInt32(controlKey | optionKey)].map { modifiers in
            ShortcutAction.allCases.map {
                ShortcutDefinition(
                    action: $0,
                    keyCode: $0.defaultKeyCode,
                    modifiers: modifiers
                )
            }
        }
    }
}

enum ShortcutPreferences {
    private static let key = "captureShortcuts.v1"

    static func load() -> [ShortcutDefinition] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ShortcutDefinition].self, from: data),
              Set(decoded.map(\.action)).count == ShortcutAction.allCases.count else {
            return ShortcutDefinition.defaults
        }
        let byAction = Dictionary(uniqueKeysWithValues: decoded.map { ($0.action, $0) })
        let ordered = ShortcutAction.allCases.compactMap { byAction[$0] }
        if ShortcutDefinition.deprecatedDefaultSets.contains(ordered) {
            save(ShortcutDefinition.defaults)
            return ShortcutDefinition.defaults
        }
        return ordered
    }

    static func save(_ shortcuts: [ShortcutDefinition]) {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum ShortcutFormatter {
    static func label(keyCode: UInt32, modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyName(keyCode)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    private static func keyName(_ code: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9", UInt32(kVK_Space): "空格",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
        ]
        return names[code] ?? "键码 \(code)"
    }
}

final class ShortcutSettingsWindowController: NSWindowController {
    typealias ApplyHandler = ([ShortcutDefinition]) -> Result<Void, Error>

    private var shortcuts: [ShortcutDefinition]
    private let initialShortcuts: [ShortcutDefinition]
    private let requiresChange: Bool
    private let applyHandler: ApplyHandler
    private var recorderButtons: [ShortcutRecorderButton] = []
    private var rowStatusImages: [NSImageView] = []
    private let statusLabel = NSTextField(labelWithString: "点击右侧按钮，然后直接按下新的快捷键组合。")
    private let saveButton = NSButton(title: "应用", target: nil, action: nil)

    init(shortcuts: [ShortcutDefinition], requiresChange: Bool = false, applyHandler: @escaping ApplyHandler) {
        self.shortcuts = shortcuts
        self.initialShortcuts = shortcuts
        self.requiresChange = requiresChange
        self.applyHandler = applyHandler
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "快捷键设置"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface(in: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildInterface(in window: NSWindow) {
        let title = NSTextField(labelWithString: "截图快捷键")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let detail = NSTextField(wrappingLabelWithString: "建议至少包含 ⌘、⌥、⌃ 或 ⇧ 中的一个修饰键。若与 CatchIt 或其他应用冲突，原设置会保持不变。")
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 12)

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.spacing = 10
        rows.alignment = .leading
        for (index, shortcut) in shortcuts.enumerated() {
            let label = NSTextField(labelWithString: shortcut.action.title)
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 180).isActive = true

            let recorder = ShortcutRecorderButton(shortcut: shortcut)
            recorder.tag = index
            recorder.onChange = { [weak self] definition in
                guard let self else { return }
                self.shortcuts[index] = definition
                self.validateShortcuts()
            }
            recorderButtons.append(recorder)
            let rowStatus = NSImageView()
            rowStatus.imageScaling = .scaleProportionallyDown
            rowStatus.translatesAutoresizingMaskIntoConstraints = false
            rowStatus.widthAnchor.constraint(equalToConstant: 18).isActive = true
            rowStatus.heightAnchor.constraint(equalToConstant: 18).isActive = true
            rowStatusImages.append(rowStatus)

            let row = NSStackView(views: [label, NSView(), rowStatus, recorder])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 456).isActive = true
            rows.addArrangedSubview(row)
        }

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2

        let defaultsButton = NSButton(title: "恢复默认", target: self, action: #selector(restoreDefaults))
        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        saveButton.target = self
        saveButton.action = #selector(apply)
        saveButton.keyEquivalent = "\r"
        let actions = NSStackView(views: [defaultsButton, NSView(), cancelButton, saveButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY

        let stack = NSStackView(views: [title, detail, rows, statusLabel, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -32),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        validateShortcuts()
    }

    @discardableResult
    private func validateShortcuts(conflictingAction: ShortcutAction? = nil) -> Bool {
        let identities = shortcuts.map { "\($0.keyCode)-\($0.modifiers)" }
        let duplicateIdentities = Set(identities.filter { identity in
            identities.filter { $0 == identity }.count > 1
        })
        let hasDuplicates = !duplicateIdentities.isEmpty
        let hasChanges = shortcuts != initialShortcuts

        for (index, imageView) in rowStatusImages.enumerated() {
            let isDuplicate = duplicateIdentities.contains(identities[index])
            let isExternalConflict = shortcuts[index].action == conflictingAction
            let isError = isDuplicate || isExternalConflict
            imageView.image = NSImage(
                systemSymbolName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
                accessibilityDescription: nil
            )
            imageView.contentTintColor = isError ? .systemRed : .systemGreen
            imageView.toolTip = isExternalConflict
                ? "该组合已被系统或其他应用占用"
                : (isDuplicate ? "与另一项重复" : "组合可用")
            imageView.setAccessibilityLabel(imageView.toolTip ?? "")
        }

        if hasDuplicates {
            statusLabel.stringValue = "存在重复快捷键，请修改标红的组合。"
            statusLabel.textColor = .systemRed
        } else if conflictingAction != nil {
            statusLabel.stringValue = "标红的快捷键已被系统或其他应用占用，请换一个组合。"
            statusLabel.textColor = .systemRed
        } else if requiresChange && !hasChanges {
            statusLabel.stringValue = "保存的组合在启动时发生冲突，请至少修改一项。原设置尚未被覆盖。"
            statusLabel.textColor = .systemOrange
        } else if !hasChanges {
            statusLabel.stringValue = "当前没有需要应用的更改。"
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = "快捷键组合有效。点击“应用”后立即生效。"
            statusLabel.textColor = .secondaryLabelColor
        }
        saveButton.isEnabled = !hasDuplicates && hasChanges
        return !hasDuplicates && hasChanges
    }

    @objc private func restoreDefaults() {
        shortcuts = ShortcutDefinition.defaults
        for (index, shortcut) in shortcuts.enumerated() { recorderButtons[index].shortcut = shortcut }
        validateShortcuts()
    }

    @objc private func cancel() { close() }

    @objc private func apply() {
        guard validateShortcuts() else { NSSound.beep(); return }
        switch applyHandler(shortcuts) {
        case .success:
            close()
        case .failure(let error):
            if let failure = error as? ShortcutRegistrationFailure {
                validateShortcuts(conflictingAction: failure.action)
            } else {
                statusLabel.stringValue = error.localizedDescription
                statusLabel.textColor = .systemRed
            }
            NSSound.beep()
        }
    }
}

struct ShortcutRegistrationFailure: LocalizedError {
    let action: ShortcutAction?
    let message: String
    var errorDescription: String? { message }
}

private final class ShortcutRecorderButton: NSButton {
    var shortcut: ShortcutDefinition { didSet { updateTitle() } }
    var onChange: ((ShortcutDefinition) -> Void)?
    private var isRecording = false

    init(shortcut: ShortcutDefinition) {
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 30))
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel("\(shortcut.action.title)快捷键")
        toolTip = "点击后按下新快捷键"
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        title = "请按快捷键…"
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            updateTitle()
            return
        }
        guard isRecording else { super.keyDown(with: event); return }
        let modifiers = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            title = "请包含修饰键"
            NSSound.beep()
            return
        }
        shortcut.keyCode = UInt32(event.keyCode)
        shortcut.modifiers = modifiers
        isRecording = false
        updateTitle()
        onChange?(shortcut)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    private func updateTitle() {
        title = shortcut.label
        setAccessibilityValue(shortcut.label)
    }
}
