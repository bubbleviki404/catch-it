import AppKit
import Foundation

let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.gaplab.catchit.selftest.\(UUID().uuidString)"))
let store = ScreenshotStore(pasteboard: pasteboard)
let oldRoot = store.rootDirectory
let temporaryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("CatchItStorageTest-\(UUID().uuidString)", isDirectory: true)
store.rootDirectory = temporaryRoot
defer {
    store.rootDirectory = oldRoot
    try? FileManager.default.removeItem(at: temporaryRoot)
}

let image = NSImage(size: NSSize(width: 80, height: 60))
image.lockFocus()
NSColor.systemBlue.setFill()
NSRect(x: 0, y: 0, width: 80, height: 60).fill()
image.unlockFocus()

let fileURL: URL
do {
    fileURL = try store.save(image, suffix: "selftest")
} catch {
    fputs("FAIL: screenshot save: \(error.localizedDescription)\n", stderr)
    exit(1)
}

guard FileManager.default.fileExists(atPath: fileURL.path),
      fileURL.pathExtension == "png",
      fileURL.deletingLastPathComponent().deletingLastPathComponent() == temporaryRoot else {
    fputs("FAIL: dated PNG path was not created correctly: \(fileURL.path)\n", stderr)
    exit(1)
}

let recent = store.recentScreenshots(limit: 4)
guard recent.first?.standardizedFileURL == fileURL.standardizedFileURL else {
    fputs("FAIL: saved screenshot did not appear in recent screenshots\nroot=\(store.rootDirectory.path)\nsaved=\(fileURL.path)\nrecent=\(recent.map(\.path))\n", stderr)
    exit(1)
}

guard let objects = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
      let pastedImage = objects.first,
      pastedImage.size.width > 0,
      pastedImage.size.height > 0 else {
    fputs("FAIL: image was not written to pasteboard\n", stderr)
    exit(1)
}

print("PASS: dated PNG saved, listed as recent, and copied to pasteboard")

var summary: ScreenshotStore.StorageSummary?
store.storageSummary { value in
    summary = value
}
let summaryDeadline = Date().addingTimeInterval(5)
while summary == nil && Date() < summaryDeadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
}
guard let summary, summary.screenshotCount == 1, summary.totalBytes > 0 else {
    fputs("FAIL: storage summary did not count the saved screenshot\n", stderr)
    exit(1)
}
print("PASS: storage summary reports screenshot count and bytes")

let invalidRoot = temporaryRoot.appendingPathComponent("not-a-directory")
try! Data("blocking file".utf8).write(to: invalidRoot)
store.rootDirectory = invalidRoot
let pasteboardChangeCount = pasteboard.changeCount
var failedSaveResult: Result<URL, Error>?
store.saveAsync(image, suffix: "must-fail") { failedSaveResult = $0 }
let deadline = Date().addingTimeInterval(5)
while failedSaveResult == nil && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
}
guard case .failure? = failedSaveResult else {
    fputs("FAIL: invalid save root should produce a recoverable failure\n", stderr)
    exit(1)
}
guard pasteboard.changeCount == pasteboardChangeCount else {
    fputs("FAIL: failed save must not replace the clipboard\n", stderr)
    exit(1)
}
print("PASS: failed save reports an error without modifying the clipboard")
