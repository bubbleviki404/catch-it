import AppKit
import CoreGraphics
import ScreenCaptureKit

final class CaptureCoordinator {
    enum Mode { case quick, annotate }
    enum Scope { case area, fullScreen }

    private let store: ScreenshotStore
    private let onStatus: (String) -> Void
    private var selector: ScreenSelectionController?
    private var editors: [UUID: AnnotationEditorWindowController] = [:]
    private var isCapturing = false

    init(store: ScreenshotStore, onStatus: @escaping (String) -> Void) {
        self.store = store
        self.onStatus = onStatus
    }

    func start(mode: Mode, scope: Scope) {
        guard !isCapturing else {
            Diagnostics.log("Capture ignored: another capture is active")
            return
        }
        guard ensureScreenCapturePermission() else {
            Diagnostics.log("Capture stopped: screen recording permission missing")
            return
        }
        Diagnostics.log("Capture started: mode=\(mode), scope=\(scope)")
        isCapturing = true

        if scope == .fullScreen {
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
            guard let screen else {
                isCapturing = false
                onStatus("找不到屏幕")
                return
            }
            capture(screen: screen, localRect: CGRect(origin: .zero, size: screen.frame.size), mode: mode)
            return
        }

        let selector = ScreenSelectionController()
        self.selector = selector
        selector.begin { [weak self] result in
            guard let self else { return }
            self.selector = nil
            switch result {
            case .cancelled:
                self.isCapturing = false
            case .selected(let screen, let rect):
                self.capture(screen: screen, localRect: rect, mode: mode)
            }
        }
    }

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if CGRequestScreenCaptureAccess() { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在“系统设置 → 隐私与安全性 → 屏幕录制”中允许 CatchIt，然后重新启动应用。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func capture(screen: NSScreen, localRect: CGRect, mode: Mode) {
        guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            isCapturing = false
            onStatus("找不到屏幕")
            return
        }
        let displayID = CGDirectDisplayID(displayNumber.uint32Value)
        let screenSize = screen.frame.size
        let backingScaleFactor = screen.backingScaleFactor

        // Give the translucent selection windows one frame to disappear.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                let cgImage = await self.captureImage(
                    displayID: displayID,
                    screenSize: screenSize,
                    backingScaleFactor: backingScaleFactor,
                    localRect: localRect
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isCapturing = false
                    self.handleCapture(cgImage, mode: mode)
                }
            }
        }
    }

    private func handleCapture(_ cgImage: CGImage?, mode: Mode) {
        guard let cgImage else {
                Diagnostics.log("Capture failed while creating CGImage")
                onStatus("截图失败")
                NSSound.beep()
                return
        }

        switch mode {
        case .quick:
            store.saveAsync(cgImage) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    Diagnostics.log("Quick capture saved: \(cgImage.width)x\(cgImage.height)")
                    self.onStatus("已保存并复制")
                case .failure(let error):
                    Diagnostics.log("Quick capture save failed: \(error.localizedDescription)")
                    self.onStatus("保存失败")
                    self.presentError(error)
                }
            }
        case .annotate:
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            let sessionID = UUID()
            let editor = AnnotationEditorWindowController(image: image, store: store) { [weak self] message in
                guard let self else { return }
                if !message.isEmpty { self.onStatus(message) }
                self.editors[sessionID] = nil
            }
            self.editors[sessionID] = editor
            editor.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func captureImage(
        displayID: CGDirectDisplayID,
        screenSize: CGSize,
        backingScaleFactor: CGFloat,
        localRect: CGRect
    ) async -> CGImage? {
        if #available(macOS 14.0, *),
           let image = await captureWithScreenCaptureKit(
               displayID: displayID,
               screenSize: screenSize,
               backingScaleFactor: backingScaleFactor,
               localRect: localRect
           ) {
            Diagnostics.log("Capture backend: ScreenCaptureKit")
            return image
        }
        Diagnostics.log("Capture backend: CoreGraphics compatibility fallback")
        return captureLegacy(displayID: displayID, screenSize: screenSize, localRect: localRect)
    }

    @available(macOS 14.0, *)
    private func captureWithScreenCaptureKit(
        displayID: CGDirectDisplayID,
        screenSize: CGSize,
        backingScaleFactor: CGFloat,
        localRect: CGRect
    ) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
            let sourceRect = CGRect(
                x: localRect.minX,
                y: screenSize.height - localRect.maxY,
                width: localRect.width,
                height: localRect.height
            ).integral.intersection(CGRect(origin: .zero, size: screenSize))
            guard sourceRect.width >= 2, sourceRect.height >= 2 else { return nil }

            let outputSize = CaptureGeometry.outputPixelSize(
                screenSize: screenSize,
                localRect: sourceRect,
                displayPixelSize: CGSize(width: display.width, height: display.height),
                backingScaleFactor: backingScaleFactor
            )

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = sourceRect
            configuration.width = Int(outputSize.width)
            configuration.height = Int(outputSize.height)
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let filter = SCContentFilter(display: display, excludingWindows: [])
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            Diagnostics.log("ScreenCaptureKit failed, using compatibility fallback: \(error.localizedDescription)")
            return nil
        }
    }

    private func captureLegacy(displayID: CGDirectDisplayID, screenSize: CGSize, localRect: CGRect) -> CGImage? {
        guard let fullImage = CGDisplayCreateImage(displayID) else { return nil }

        let sx = CGFloat(fullImage.width) / screenSize.width
        let sy = CGFloat(fullImage.height) / screenSize.height
        let crop = CGRect(
            x: localRect.minX * sx,
            y: (screenSize.height - localRect.maxY) * sy,
            width: localRect.width * sx,
            height: localRect.height * sy
        ).integral.intersection(CGRect(x: 0, y: 0, width: fullImage.width, height: fullImage.height))

        guard crop.width >= 2, crop.height >= 2 else { return nil }
        return fullImage.cropping(to: crop)
    }

    private func presentError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
