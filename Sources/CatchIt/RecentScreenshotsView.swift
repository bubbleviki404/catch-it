import AppKit
import ImageIO

final class RecentScreenshotsView: NSView {
    private let onSelect: (URL) -> Void
    private var currentURLs: [URL] = []
    private let thumbnailCache = NSCache<NSURL, NSImage>()
    private let thumbnailQueue = DispatchQueue(label: "com.gaplab.catchit.thumbnails", qos: .utility)

    init(onSelect: @escaping (URL) -> Void) {
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 352, height: 104))
        update(urls: [])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(urls: [URL]) {
        currentURLs = urls
        subviews.forEach { $0.removeFromSuperview() }
        if urls.isEmpty {
            let empty = NSTextField(labelWithString: "还没有截图")
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: 13)
            empty.alignment = .center
            empty.frame = bounds.insetBy(dx: 12, dy: 38)
            addSubview(empty)
            return
        }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for url in urls {
            stack.addArrangedSubview(makeThumbnail(url: url))
        }
        for _ in urls.count..<4 {
            stack.addArrangedSubview(NSView())
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    private func makeThumbnail(url: URL) -> NSView {
        let container = NSView()
        let button = RecentScreenshotButton(url: url, target: self, action: #selector(selectScreenshot(_:)))
        button.image = thumbnailCache.object(forKey: url as NSURL)
            ?? NSImage(systemSymbolName: "photo", accessibilityDescription: "正在载入缩略图")
        button.imageScaling = .scaleProportionallyUpOrDown
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        button.toolTip = "点击复制：\(url.lastPathComponent)"
        button.menu = makeContextMenu(for: url)
        button.translatesAutoresizingMaskIntoConstraints = false

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let time = NSTextField(labelWithString: formatter.string(from: modified))
        time.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        time.textColor = .secondaryLabelColor
        time.alignment = .center
        time.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(button)
        container.addSubview(time)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.heightAnchor.constraint(equalToConstant: 66),
            time.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 4),
            time.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            time.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            time.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])
        loadThumbnail(for: url, into: button)
        return container
    }

    private func loadThumbnail(for url: URL, into button: RecentScreenshotButton) {
        if let cached = thumbnailCache.object(forKey: url as NSURL) {
            button.image = cached
            return
        }
        thumbnailQueue.async { [weak self, weak button] in
            guard let self,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 180
                  ] as CFDictionary) else { return }
            let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            self.thumbnailCache.setObject(thumbnail, forKey: url as NSURL)
            DispatchQueue.main.async {
                guard let button, button.url == url else { return }
                button.image = thumbnail
            }
        }
    }

    @objc private func selectScreenshot(_ sender: RecentScreenshotButton) {
        onSelect(sender.url)
    }

    private func makeContextMenu(for url: URL) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: "复制到剪贴板", symbol: "doc.on.doc", action: #selector(copyFromMenu(_:)), url: url))
        menu.addItem(makeMenuItem(title: "在 Finder 中显示", symbol: "folder", action: #selector(revealInFinder(_:)), url: url))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "移到废纸篓", symbol: "trash", action: #selector(moveToTrash(_:)), url: url))
        return menu
    }

    private func makeMenuItem(title: String, symbol: String, action: Selector, url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.target = self
        item.representedObject = url as NSURL
        return item
    }

    private func url(from item: NSMenuItem) -> URL? {
        (item.representedObject as? NSURL).map { $0 as URL }
    }

    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        guard let url = url(from: sender) else { return }
        onSelect(url)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let url = url(from: sender) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func moveToTrash(_ sender: NSMenuItem) {
        guard let url = url(from: sender) else { return }
        NSWorkspace.shared.recycle([url]) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    NSAlert(error: error).runModal()
                    return
                }
                guard let self else { return }
                self.update(urls: self.currentURLs.filter { $0 != url })
            }
        }
    }
}

private final class RecentScreenshotButton: NSButton {
    let url: URL

    init(url: URL, target: AnyObject?, action: Selector?) {
        self.url = url
        super.init(frame: .zero)
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
