import AppKit
import CoreGraphics
import ServiceManagement

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let quickArea: () -> Void
    private let quickFullScreen: () -> Void
    private let annotateArea: () -> Void
    private let annotateFullScreen: () -> Void
    private let openTodayFolder: () -> Void
    private let saveRootDirectory: () -> URL
    private let openShortcutSettings: () -> Void
    private let openStorageSettings: () -> Void

    private let permissionDot = NSView()
    private let permissionTitle = NSTextField(labelWithString: "")
    private let permissionDetail = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton()
    private let storageDescription = NSTextField(wrappingLabelWithString: "")
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)
    private var captureButtons: [ShortcutAction: NSButton] = [:]
    private var initialShortcuts: [ShortcutDefinition]

    init(
        quickArea: @escaping () -> Void,
        quickFullScreen: @escaping () -> Void,
        annotateArea: @escaping () -> Void,
        annotateFullScreen: @escaping () -> Void,
        openTodayFolder: @escaping () -> Void,
        saveRootDirectory: @escaping () -> URL,
        openShortcutSettings: @escaping () -> Void,
        openStorageSettings: @escaping () -> Void,
        shortcuts: [ShortcutDefinition]
    ) {
        self.quickArea = quickArea
        self.quickFullScreen = quickFullScreen
        self.annotateArea = annotateArea
        self.annotateFullScreen = annotateFullScreen
        self.openTodayFolder = openTodayFolder
        self.saveRootDirectory = saveRootDirectory
        self.openShortcutSettings = openShortcutSettings
        self.openStorageSettings = openStorageSettings
        self.initialShortcuts = shortcuts

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CatchIt"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildInterface(in: window)
        refreshPermissionStatus()
        refreshStorageDescription()
        refreshLaunchAtLoginStatus()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshPermissionStatus() {
        let granted = CGPreflightScreenCaptureAccess()
        permissionDot.layer?.backgroundColor = (granted ? NSColor.systemGreen : NSColor.systemOrange).cgColor
        permissionTitle.stringValue = granted ? "屏幕录制权限正常" : "需要重新授权屏幕录制"
        permissionDetail.stringValue = granted
            ? "CatchIt 已可以读取屏幕内容，截图快捷键可以使用。"
            : "如果系统设置中已经开启但这里仍显示未授权，请先关闭 CatchIt，移除旧授权后重新打开并授权。"
        permissionButton.title = granted ? "重新检查" : "打开系统设置"
    }

    func refreshStorageDescription() {
        let path = (saveRootDirectory().path as NSString).abbreviatingWithTildeInPath
        storageDescription.stringValue = "按日期保存到“\(path)/年-月-日”，并复制到剪贴板。关闭窗口后仍会继续运行。"
    }

    func updateShortcutLabels(_ shortcuts: [ShortcutDefinition]) {
        for shortcut in shortcuts {
            captureButtons[shortcut.action]?.title = "\(shortcut.action.title)    \(shortcut.label)"
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshPermissionStatus()
        refreshLaunchAtLoginStatus()
    }

    private func buildInterface(in window: NSWindow) {
        guard let content = window.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let header = makeHeader()
        let permissionCard = makePermissionCard()
        let captureSections = makeCaptureSections()

        let folderButton = NSButton(title: "打开今日截图目录", target: self, action: #selector(openFolder))
        folderButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        folderButton.imagePosition = .imageLeading
        folderButton.bezelStyle = .rounded
        let storageButton = NSButton(title: "管理存储…", target: self, action: #selector(showStorageSettings))
        storageButton.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: nil)
        storageButton.imagePosition = .imageLeading
        storageButton.bezelStyle = .rounded

        storageDescription.textColor = .secondaryLabelColor
        storageDescription.font = .systemFont(ofSize: 12)
        storageDescription.maximumNumberOfLines = 2

        let footer = NSStackView(views: [folderButton, storageButton, storageDescription])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 14

        let rootStack = NSStackView(views: [header, permissionCard, captureSections, footer])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 20
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            rootStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 34),
            rootStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            header.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            permissionCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            captureSections.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
    }

    private func makeHeader() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "CatchIt")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        let subtitle = NSTextField(labelWithString: "截图助手正在运行")
        subtitle.font = .systemFont(ofSize: 14, weight: .medium)
        subtitle.textColor = .systemGreen
        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(toggleLaunchAtLogin(_:))
        launchAtLoginButton.toolTip = "登录 Mac 后自动运行 CatchIt"
        launchAtLoginButton.setAccessibilityLabel("登录时启动 CatchIt")

        let shortcutButton = NSButton(title: "快捷键设置…", target: self, action: #selector(showShortcutSettings))
        shortcutButton.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        shortcutButton.imagePosition = .imageLeading
        shortcutButton.bezelStyle = .rounded
        shortcutButton.toolTip = "修改四个全局截图快捷键"

        let spacer = NSView()
        let header = NSStackView(views: [icon, textStack, spacer, shortcutButton, launchAtLoginButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64)
        ])
        return header
    }

    private func makePermissionCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor

        permissionDot.wantsLayer = true
        permissionDot.layer?.cornerRadius = 5
        permissionDot.translatesAutoresizingMaskIntoConstraints = false

        permissionTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        permissionDetail.font = .systemFont(ofSize: 12)
        permissionDetail.textColor = .secondaryLabelColor
        permissionDetail.maximumNumberOfLines = 2
        let textStack = NSStackView(views: [permissionTitle, permissionDetail])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        permissionButton.target = self
        permissionButton.action = #selector(permissionAction)
        permissionButton.bezelStyle = .rounded

        let row = NSStackView(views: [permissionDot, textStack, NSView(), permissionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 82),
            permissionDot.widthAnchor.constraint(equalToConstant: 10),
            permissionDot.heightAnchor.constraint(equalToConstant: 10),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            row.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textStack.widthAnchor.constraint(lessThanOrEqualToConstant: 430)
        ])
        return card
    }

    private func makeCaptureSections() -> NSView {
        let quickAreaButton = makeCaptureButton(action: .quickArea, symbol: "viewfinder", selector: #selector(runQuickArea))
        let quickFullButton = makeCaptureButton(action: .quickFullScreen, symbol: "rectangle.inset.filled", selector: #selector(runQuickFull))
        let editAreaButton = makeCaptureButton(action: .annotateArea, symbol: "pencil.and.outline", selector: #selector(runAnnotateArea))
        let editFullButton = makeCaptureButton(action: .annotateFullScreen, symbol: "rectangle.and.pencil.and.ellipsis", selector: #selector(runAnnotateFull))

        let quickSection = makeCaptureSection(
            title: "直接截图",
            detail: "保存并复制",
            buttons: [quickAreaButton, quickFullButton]
        )
        let editSection = makeCaptureSection(
            title: "截图后编辑",
            detail: "标注、马赛克与裁剪",
            buttons: [editAreaButton, editFullButton]
        )
        let sections = NSStackView(views: [quickSection, editSection])
        sections.orientation = .vertical
        sections.alignment = .leading
        sections.spacing = 16
        quickSection.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true
        editSection.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true
        return sections
    }

    private func makeCaptureSection(title: String, detail: String, buttons: [NSButton]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [titleLabel, detailLabel, NSView()])
        heading.orientation = .horizontal
        heading.alignment = .firstBaseline
        heading.spacing = 8

        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12

        let section = NSStackView(views: [heading, row])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        heading.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        row.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func makeCaptureButton(action: ShortcutAction, symbol: String, selector: Selector) -> NSButton {
        let shortcut = initialShortcuts.first { $0.action == action }
        let title = shortcut.map { "\(action.title)    \($0.label)" } ?? action.title
        let button = NSButton(title: title, target: self, action: selector)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        captureButtons[action] = button
        return button
    }

    @objc private func permissionAction() {
        if CGPreflightScreenCaptureAccess() {
            refreshPermissionStatus()
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            refreshLaunchAtLoginStatus()
            let alert = NSAlert(error: error)
            alert.messageText = "无法更新登录启动设置"
            if let window { alert.beginSheetModal(for: window) }
        }
    }

    @objc private func showShortcutSettings() { openShortcutSettings() }
    @objc private func showStorageSettings() { openStorageSettings() }

    @objc private func openFolder() { openTodayFolder() }
    @objc private func runQuickArea() { quickArea() }
    @objc private func runQuickFull() { quickFullScreen() }
    @objc private func runAnnotateArea() { annotateArea() }
    @objc private func runAnnotateFull() { annotateFullScreen() }
}
