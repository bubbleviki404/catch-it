import AppKit

final class StorageSettingsWindowController: NSWindowController {
    private let store: ScreenshotStore
    private let onOpenFolder: () -> Void
    private let onChanged: () -> Void
    private let usageLabel = NSTextField(labelWithString: "正在计算占用空间…")
    private let retentionPopup = NSPopUpButton()
    private let cleanupButton = NSButton(title: "立即清理…", target: nil, action: nil)

    init(store: ScreenshotStore, onOpenFolder: @escaping () -> Void, onChanged: @escaping () -> Void) {
        self.store = store
        self.onOpenFolder = onOpenFolder
        self.onChanged = onChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "存储管理"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface(in: window)
        refreshSummary()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildInterface(in window: NSWindow) {
        let title = NSTextField(labelWithString: "截图存储")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let path = (store.rootDirectory.path as NSString).abbreviatingWithTildeInPath
        let pathLabel = NSTextField(wrappingLabelWithString: path)
        pathLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        usageLabel.font = .systemFont(ofSize: 14, weight: .medium)

        let policyLabel = NSTextField(labelWithString: "保留策略")
        policyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        policyLabel.translatesAutoresizingMaskIntoConstraints = false
        policyLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true

        ScreenshotStore.RetentionPolicy.allCases.forEach { policy in
            retentionPopup.addItem(withTitle: policy.title)
            retentionPopup.lastItem?.representedObject = policy.rawValue
        }
        retentionPopup.target = self
        retentionPopup.action = #selector(retentionChanged)
        selectCurrentPolicy()

        let policyRow = NSStackView(views: [policyLabel, retentionPopup, NSView()])
        policyRow.orientation = .horizontal
        policyRow.alignment = .centerY

        let policyDetail = NSTextField(wrappingLabelWithString: "CatchIt 不会自动删除截图。选择保留期限后，可随时把更早的截图移到废纸篓。")
        policyDetail.font = .systemFont(ofSize: 12)
        policyDetail.textColor = .secondaryLabelColor

        let openButton = NSButton(title: "打开截图目录", target: self, action: #selector(openFolder))
        cleanupButton.target = self
        cleanupButton.action = #selector(cleanup)
        let doneButton = NSButton(title: "完成", target: self, action: #selector(done))
        doneButton.keyEquivalent = "\r"

        let actions = NSStackView(views: [openButton, cleanupButton, NSView(), doneButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY

        let stack = NSStackView(views: [title, pathLabel, usageLabel, policyRow, policyDetail, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 26),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -32),
            pathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            policyRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            policyDetail.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        updateCleanupAvailability()
    }

    private func refreshSummary() {
        usageLabel.stringValue = "正在计算占用空间…"
        store.storageSummary { [weak self] summary in
            guard let self else { return }
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let size = formatter.string(fromByteCount: summary.totalBytes)
            self.usageLabel.stringValue = "共 \(summary.screenshotCount) 张截图，占用 \(size)"
        }
    }

    private var selectedPolicy: ScreenshotStore.RetentionPolicy {
        guard let raw = retentionPopup.selectedItem?.representedObject as? Int else { return .forever }
        return ScreenshotStore.RetentionPolicy(rawValue: raw) ?? .forever
    }

    private func selectCurrentPolicy() {
        let raw = store.retentionPolicy.rawValue
        if let index = retentionPopup.itemArray.firstIndex(where: { ($0.representedObject as? Int) == raw }) {
            retentionPopup.selectItem(at: index)
        }
    }

    private func updateCleanupAvailability() {
        cleanupButton.isEnabled = selectedPolicy != .forever
    }

    @objc private func retentionChanged() {
        store.retentionPolicy = selectedPolicy
        updateCleanupAvailability()
        onChanged()
    }

    @objc private func cleanup() {
        let policy = selectedPolicy
        guard policy != .forever, let window else { return }
        let alert = NSAlert()
        alert.messageText = "清理超过 \(policy.rawValue) 天的截图？"
        alert.informativeText = "符合条件的 CatchIt 截图会移到废纸篓，可以从废纸篓恢复。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.cleanupButton.isEnabled = false
            self.store.moveExpiredScreenshotsToTrash(policy: policy) { [weak self] result in
                guard let self else { return }
                self.updateCleanupAvailability()
                switch result {
                case .success(let count):
                    self.refreshSummary()
                    self.onChanged()
                    self.usageLabel.stringValue = count == 0 ? "没有需要清理的过期截图" : "已将 \(count) 张截图移到废纸篓"
                case .failure(let error):
                    let errorAlert = NSAlert(error: error)
                    errorAlert.beginSheetModal(for: window)
                }
            }
        }
    }

    @objc private func openFolder() { onOpenFolder() }
    @objc private func done() { close() }
}
