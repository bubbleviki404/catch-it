import AppKit
import Foundation

let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.gaplab.catchit.performance.\(UUID().uuidString)"))
let store = ScreenshotStore(pasteboard: pasteboard)
let oldRoot = store.rootDirectory
let temporaryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("CatchItPerformanceTest-\(UUID().uuidString)", isDirectory: true)
store.rootDirectory = temporaryRoot
defer {
    store.rootDirectory = oldRoot
    try? FileManager.default.removeItem(at: temporaryRoot)
}

let width = 1800
let height = 1200
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let pixels = bitmap.bitmapData else {
    fputs("FAIL: could not create performance image\n", stderr)
    exit(1)
}
arc4random_buf(pixels, bitmap.bytesPerRow * height)
let image = NSImage(size: NSSize(width: width, height: height))
image.addRepresentation(bitmap)

var completionResult: Result<URL, Error>?
var mainQueueStayedResponsive = false
var completionWasOnMainThread = false
let callStart = CFAbsoluteTimeGetCurrent()
store.saveAsync(image, suffix: "performance") { result in
    completionWasOnMainThread = Thread.isMainThread
    completionResult = result
}
let schedulingDuration = CFAbsoluteTimeGetCurrent() - callStart
DispatchQueue.main.async { mainQueueStayedResponsive = true }

let deadline = Date().addingTimeInterval(10)
while completionResult == nil && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
}

guard schedulingDuration < 0.10 else {
    fputs("FAIL: async save blocked caller for \(schedulingDuration)s\n", stderr)
    exit(1)
}
guard mainQueueStayedResponsive else {
    fputs("FAIL: main queue did not run while image encoded\n", stderr)
    exit(1)
}
guard completionWasOnMainThread else {
    fputs("FAIL: async save completion was not delivered on main thread\n", stderr)
    exit(1)
}
guard case .success(let url)? = completionResult,
      FileManager.default.fileExists(atPath: url.path),
      pasteboard.data(forType: .png) != nil,
      pasteboard.data(forType: .tiff) != nil else {
    fputs("FAIL: async save did not publish file, PNG and TIFF\n", stderr)
    exit(1)
}

print("PASS: async save returned in \(String(format: "%.3f", schedulingDuration))s and kept main queue responsive")
