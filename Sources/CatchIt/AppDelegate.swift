import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private lazy var hotKeys = HotKeyManager()
    private lazy var captureCoordinator = CaptureCoordinator(store: store) { [weak self] message in
        self?.showStatus(message)
    }
    private let store = ScreenshotStore()
    private let feedbackPresenter = FeedbackPresenter()
    private let updateChecker = UpdateChecker()
    private var shortcutStatusItem: NSMenuItem?
    private var shortcutMenuItems: [ShortcutAction: NSMenuItem] = [:]
    private var activeShortcuts = ShortcutPreferences.load()
    private var conflictedSavedShortcuts: [ShortcutDefinition]?
    private var startupShortcutConflictMessage: String?
    private var shortcutSettingsWindowController: ShortcutSettingsWindowController?
    private var storageSettingsWindowController: StorageSettingsWindowController?
    private var mainWindowController: MainWindowController?
    private var recentScreenshotsView: RecentScreenshotsView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.reset()
        configureStatusItem()
        registerHotKeys()
        configureMainWindow()
        if let message = startupShortcutConflictMessage {
            DispatchQueue.main.async { [weak self] in self?.presentStartupShortcutConflict(message) }
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 20)
        if let button = statusItem.button {
            configureStatusButton(button)
        }

        let menu = NSMenu()
        menu.delegate = self

        let recentTitle = NSMenuItem(title: "最近截图", action: nil, keyEquivalent: "")
        recentTitle.isEnabled = false
        menu.addItem(recentTitle)
        let recentItem = NSMenuItem()
        let recentView = RecentScreenshotsView { [weak self] url in
            guard let self else { return }
            self.store.copyFileToPasteboardAsync(url) { [weak self] result in
                switch result {
                case .success: self?.showStatus("已重新复制")
                case .failure(let error):
                    Diagnostics.log("Recent screenshot copy failed: \(error.localizedDescription)")
                    self?.showStatus("复制失败")
                }
            }
        }
        recentScreenshotsView = recentView
        recentItem.view = recentView
        menu.addItem(recentItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "显示 CatchIt", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "关于 CatchIt", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(makeShortcutItem(action: .quickArea, selector: #selector(quickAreaCapture)))
        menu.addItem(makeShortcutItem(action: .quickFullScreen, selector: #selector(quickFullScreenCapture)))
        menu.addItem(.separator())
        menu.addItem(makeShortcutItem(action: .annotateArea, selector: #selector(editAreaCapture)))
        menu.addItem(makeShortcutItem(action: .annotateFullScreen, selector: #selector(editFullScreenCapture)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开今日截图目录", action: #selector(openTodayFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "更改保存位置…", action: #selector(changeSaveFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "管理存储…", action: #selector(showStorageSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "快捷键设置…", action: #selector(showShortcutSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        let status = NSMenuItem(title: "快捷键：正在注册…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        shortcutStatusItem = status
        menu.addItem(status)
        menu.addItem(NSMenuItem(title: "使用说明", action: #selector(showHelp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出 CatchIt", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.isVisible = true
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.isVisible = true
        }
    }

    private func configureStatusButton(_ button: NSStatusBarButton) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "CatchIt 截图")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.image = image
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = image == nil ? .noImage : .imageOnly
        button.title = image == nil ? "截" : ""
        button.font = .systemFont(ofSize: 14, weight: .bold)
        button.toolTip = "CatchIt 截图"
        button.setAccessibilityLabel("CatchIt 截图")
    }

    func menuWillOpen(_ menu: NSMenu) {
        recentScreenshotsView?.update(urls: store.recentScreenshots(limit: 4))
        mainWindowController?.refreshPermissionStatus()
    }

    private func configureMainWindow() {
        let controller = MainWindowController(
            quickArea: { [weak self] in self?.quickAreaCapture() },
            quickFullScreen: { [weak self] in self?.quickFullScreenCapture() },
            annotateArea: { [weak self] in self?.editAreaCapture() },
            annotateFullScreen: { [weak self] in self?.editFullScreenCapture() },
            openTodayFolder: { [weak self] in self?.openTodayFolder() },
            saveRootDirectory: { [weak self] in self?.store.rootDirectory ?? FileManager.default.homeDirectoryForCurrentUser },
            openShortcutSettings: { [weak self] in self?.showShortcutSettings() },
            openStorageSettings: { [weak self] in self?.showStorageSettings() },
            shortcuts: activeShortcuts
        )
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func registerHotKeys() {
        do {
            try installShortcuts(activeShortcuts)
            updateShortcutPresentation()
        } catch {
            Diagnostics.log("Stored shortcut registration failed: \(error.localizedDescription)")
            conflictedSavedShortcuts = activeShortcuts
            hotKeys.unregisterAll()
            let defaults = ShortcutDefinition.defaults
            do {
                try installShortcuts(defaults)
                activeShortcuts = defaults
                updateShortcutPresentation()
                startupShortcutConflictMessage = "保存的快捷键发生冲突，CatchIt 暂时启用了默认组合，但没有覆盖你的设置。请修改冲突项。\n\n\(error.localizedDescription)"
            } catch {
                shortcutStatusItem?.title = "快捷键注册失败"
                activeShortcuts = []
                startupShortcutConflictMessage = "保存的快捷键和备用组合都无法注册。你的原设置仍然保留，请立即修改。\n\n\(error.localizedDescription)"
            }
        }
    }

    private func installShortcuts(_ shortcuts: [ShortcutDefinition]) throws {
        hotKeys.unregisterAll()
        for shortcut in shortcuts {
            do {
                try hotKeys.register(
                    keyCode: shortcut.keyCode,
                    modifiers: HotKeyManager.Modifiers(rawValue: shortcut.modifiers),
                    handler: handler(for: shortcut.action)
                )
            } catch {
                throw ShortcutRegistrationFailure(
                    action: shortcut.action,
                    message: "\(shortcut.action.title)（\(shortcut.label)）无法注册：\(error.localizedDescription)"
                )
            }
            Diagnostics.log("Registered hot key \(shortcut.label) for \(shortcut.action.rawValue)")
        }
    }

    private func handler(for action: ShortcutAction) -> () -> Void {
        { [weak self] in
            switch action {
            case .quickArea: self?.quickAreaCapture()
            case .quickFullScreen: self?.quickFullScreenCapture()
            case .annotateArea: self?.editAreaCapture()
            case .annotateFullScreen: self?.editFullScreenCapture()
            }
        }
    }

    private func makeShortcutItem(action: ShortcutAction, selector: Selector) -> NSMenuItem {
        let shortcut = activeShortcuts.first { $0.action == action }
        let item = NSMenuItem(title: menuTitle(action: action, shortcut: shortcut), action: selector, keyEquivalent: "")
        shortcutMenuItems[action] = item
        return item
    }

    private func menuTitle(action: ShortcutAction, shortcut: ShortcutDefinition?) -> String {
        shortcut.map { "\(action.title)    \($0.label)" } ?? action.title
    }

    private func updateShortcutPresentation() {
        for shortcut in activeShortcuts {
            shortcutMenuItems[shortcut.action]?.title = menuTitle(action: shortcut.action, shortcut: shortcut)
        }
        shortcutStatusItem?.title = "快捷键：4/4 已启用"
    }

    private func applyShortcuts(_ shortcuts: [ShortcutDefinition]) -> Result<Void, Error> {
        let previous = activeShortcuts
        do {
            try installShortcuts(shortcuts)
            activeShortcuts = shortcuts
            conflictedSavedShortcuts = nil
            ShortcutPreferences.save(shortcuts)
            updateShortcutPresentation()
            mainWindowController?.updateShortcutLabels(shortcuts)
            showStatus("快捷键已更新")
            return .success(())
        } catch {
            Diagnostics.log("Shortcut update failed, rolling back: \(error.localizedDescription)")
            hotKeys.unregisterAll()
            do {
                try installShortcuts(previous)
            } catch let rollbackError {
                activeShortcuts = []
                shortcutStatusItem?.title = "快捷键：恢复失败"
                return .failure(ShortcutRegistrationFailure(
                    action: (error as? ShortcutRegistrationFailure)?.action,
                    message: "新组合发生冲突，原快捷键也未能恢复。请立即选择其他组合。\n\(rollbackError.localizedDescription)"
                ))
            }
            activeShortcuts = previous
            updateShortcutPresentation()
            let conflict = error as? ShortcutRegistrationFailure
            return .failure(ShortcutRegistrationFailure(
                action: conflict?.action,
                message: "新快捷键未生效，原设置已保留。\n\(conflict?.localizedDescription ?? error.localizedDescription)"
            ))
        }
    }

    @objc private func showShortcutSettings() {
        let draft = conflictedSavedShortcuts ?? activeShortcuts
        let controller = ShortcutSettingsWindowController(
            shortcuts: draft,
            requiresChange: conflictedSavedShortcuts != nil
        ) { [weak self] shortcuts in
            self?.applyShortcuts(shortcuts) ?? .failure(NSError(
                domain: "CatchIt.Shortcuts",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "CatchIt 已关闭，无法更新快捷键。"]
            ))
        }
        shortcutSettingsWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentStartupShortcutConflict(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "快捷键需要调整"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "修改快捷键")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn { showShortcutSettings() }
    }

    @objc private func showMainWindow() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.refreshPermissionStatus()
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showStorageSettings() {
        let controller = StorageSettingsWindowController(
            store: store,
            onOpenFolder: { [weak self] in self?.openTodayFolder() },
            onChanged: { [weak self] in self?.mainWindowController?.refreshStorageDescription() }
        )
        storageSettingsWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quickAreaCapture() {
        Diagnostics.log("Action: quick area")
        captureCoordinator.start(mode: .quick, scope: .area)
    }

    @objc private func quickFullScreenCapture() {
        Diagnostics.log("Action: quick full screen")
        captureCoordinator.start(mode: .quick, scope: .fullScreen)
    }

    @objc private func editAreaCapture() {
        Diagnostics.log("Action: annotate area")
        captureCoordinator.start(mode: .annotate, scope: .area)
    }

    @objc private func editFullScreenCapture() {
        Diagnostics.log("Action: annotate full screen")
        captureCoordinator.start(mode: .annotate, scope: .fullScreen)
    }

    @objc private func openTodayFolder() {
        do {
            NSWorkspace.shared.open(try store.todayDirectory())
        } catch {
            showAlert(title: "无法打开目录", message: error.localizedDescription)
        }
    }

    @objc private func changeSaveFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择 CatchIt 保存目录"
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.rootDirectory
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            store.rootDirectory = url
            mainWindowController?.refreshStorageDescription()
            showStatus("保存位置已更新")
        }
    }

    @objc private func showHelp() {
        showAlert(
            title: "CatchIt 使用说明",
            message: activeShortcuts.map { "\($0.label)：\($0.action.title)" }.joined(separator: "\n") + "\n\n可从主窗口或菜单栏打开“快捷键设置…”。框选界面也可点击顶部的“截取此屏幕”，按 Esc 取消。编辑器支持矩形、马赛克、便签、文字与裁剪；选中后可拖动圆点缩放或按 Delete 删除，矩形/便签/文字可换色，双击便签/文字可直接修改。按 ⌘S 保存。"
        )
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let credits = NSAttributedString(
            string: "轻量、原生、只在本机处理截图。\n版本 \(version)（\(build)）",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        showStatus("正在检查更新…")
        updateChecker.check { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.upToDate(let currentVersion)):
                self.showAlert(title: "已是最新版本", message: "CatchIt \(currentVersion) 当前无需更新。")
            case .success(.updateAvailable(_, let latestVersion, let downloadURL, let notes)):
                let alert = NSAlert()
                alert.messageText = "发现 CatchIt \(latestVersion)"
                let summary = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let summary, !summary.isEmpty {
                    alert.informativeText = String(summary.prefix(700))
                } else {
                    alert.informativeText = "GitHub 上已有新版本。"
                }
                alert.addButton(withTitle: "前往下载")
                alert.addButton(withTitle: "稍后")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(downloadURL) }
            case .failure(let error):
                self.showAlert(title: "暂时无法检查更新", message: error.localizedDescription)
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showStatus(_ message: String) {
        feedbackPresenter.show(message, style: feedbackStyle(for: message))
        // Keep the menu-bar item at a stable width. Transient status text made
        // the icon disappear first when the menu bar was crowded.
        statusItem.length = 20
        if let button = statusItem.button { configureStatusButton(button) }
        statusItem.isVisible = true
    }

    private func feedbackStyle(for message: String) -> FeedbackPresenter.Style {
        if message.contains("失败") || message.contains("无法") || message.contains("冲突") { return .error }
        if message.contains("取消") { return .info }
        return .success
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
}
