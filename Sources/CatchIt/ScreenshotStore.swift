import AppKit
import ImageIO

final class ScreenshotStore {
    struct StorageSummary {
        let screenshotCount: Int
        let totalBytes: Int64
    }

    enum RetentionPolicy: Int, CaseIterable {
        case forever = 0
        case thirtyDays = 30
        case ninetyDays = 90
        case oneHundredEightyDays = 180

        var title: String {
            switch self {
            case .forever: return "永久保留"
            case .thirtyDays: return "保留 30 天"
            case .ninetyDays: return "保留 90 天"
            case .oneHundredEightyDays: return "保留 180 天"
            }
        }
    }

    private struct EncodedImage {
        let png: Data
        let tiff: Data
    }

    private enum StoreError: Error {
        case imageConversionFailed
        case imageEncodingFailed
    }

    private let rootKey = "screenshotRootDirectory"
    private let retentionKey = "screenshotRetentionDays"
    private let pasteboard: NSPasteboard
    private let ioQueue = DispatchQueue(label: "com.gaplab.catchit.image-io", qos: .userInitiated)

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var rootDirectory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: rootKey) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            return pictures.appendingPathComponent("CatchIt", isDirectory: true)
        }
        set { UserDefaults.standard.set(newValue.path, forKey: rootKey) }
    }

    var retentionPolicy: RetentionPolicy {
        get { RetentionPolicy(rawValue: UserDefaults.standard.integer(forKey: retentionKey)) ?? .forever }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: retentionKey) }
    }

    func storageSummary(completion: @escaping (StorageSummary) -> Void) {
        let root = rootDirectory
        ioQueue.async {
            let files = Self.screenshotFiles(in: root)
            let bytes = files.reduce(Int64(0)) { partial, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return partial + Int64(size)
            }
            DispatchQueue.main.async {
                completion(StorageSummary(screenshotCount: files.count, totalBytes: bytes))
            }
        }
    }

    func expiredScreenshotCount(for policy: RetentionPolicy) -> Int {
        guard policy != .forever else { return 0 }
        return Self.expiredScreenshotFiles(in: rootDirectory, days: policy.rawValue).count
    }

    func moveExpiredScreenshotsToTrash(
        policy: RetentionPolicy,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard policy != .forever else { completion(.success(0)); return }
        let urls = Self.expiredScreenshotFiles(in: rootDirectory, days: policy.rawValue)
        guard !urls.isEmpty else { completion(.success(0)); return }
        NSWorkspace.shared.recycle(urls) { _, error in
            DispatchQueue.main.async {
                if let error { completion(.failure(error)) }
                else { completion(.success(urls.count)) }
            }
        }
    }

    func todayDirectory() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let directory = rootDirectory.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Synchronous compatibility path used by small utility operations and tests.
    /// PNG and TIFF are each encoded once, then reused for disk and pasteboard.
    @discardableResult
    func save(_ image: NSImage, suffix: String = "") throws -> URL {
        guard let cgImage = image.catchItCGImage else { throw StoreError.imageConversionFailed }
        let encoded = try encode(cgImage)
        let fileURL = try write(encoded.png, suffix: suffix)
        publishToPasteboard(encoded)
        return fileURL
    }

    /// Performs compression and file I/O away from the main thread. Completion
    /// always runs on the main thread after the pasteboard has been updated.
    func saveAsync(
        _ cgImage: CGImage,
        suffix: String = "",
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        ioQueue.async { [self] in
            let result: Result<(URL, EncodedImage), Error> = Result {
                let encoded = try encode(cgImage)
                let fileURL = try write(encoded.png, suffix: suffix)
                return (fileURL, encoded)
            }
            DispatchQueue.main.async { [self] in
                switch result {
                case .success(let value):
                    publishToPasteboard(value.1)
                    completion(.success(value.0))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func saveAsync(
        _ image: NSImage,
        suffix: String = "",
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let cgImage = image.catchItCGImage else {
            completion(.failure(StoreError.imageConversionFailed))
            return
        }
        saveAsync(cgImage, suffix: suffix, completion: completion)
    }

    func copyToPasteboard(_ image: NSImage) {
        guard let cgImage = image.catchItCGImage,
              let encoded = try? encode(cgImage) else {
            pasteboard.clearContents()
            _ = pasteboard.writeObjects([image])
            return
        }
        publishToPasteboard(encoded)
    }

    /// Reuses the PNG bytes already on disk instead of decoding and re-encoding
    /// them. TIFF compatibility data is prepared on the image I/O queue.
    func copyFileToPasteboardAsync(
        _ url: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        ioQueue.async { [self] in
            let result: Result<EncodedImage, Error> = Result {
                let png = try Data(contentsOf: url, options: .mappedIfSafe)
                guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw StoreError.imageConversionFailed
                }
                return EncodedImage(png: png, tiff: try encode(cgImage, type: "public.tiff" as CFString))
            }
            DispatchQueue.main.async { [self] in
                switch result {
                case .success(let encoded):
                    publishToPasteboard(encoded)
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    /// The storage layout is date-based, so newest folders and filenames can be
    /// traversed directly. This avoids recursively loading and sorting years of
    /// screenshots every time the menu opens.
    func recentScreenshots(limit: Int) -> [URL] {
        guard limit > 0,
              let dayDirectories = try? FileManager.default.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        let validDayName = try? NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
        let sortedDays = dayDirectories.filter { url in
            let range = NSRange(url.lastPathComponent.startIndex..., in: url.lastPathComponent)
            let matchesDate = validDayName?.firstMatch(in: url.lastPathComponent, range: range) != nil
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return matchesDate && isDirectory
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }

        var result: [URL] = []
        for directory in sortedDays {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            let screenshots = files.filter {
                $0.pathExtension.lowercased() == "png" && $0.lastPathComponent.hasPrefix("CatchIt-")
            }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            result.append(contentsOf: screenshots.prefix(limit - result.count))
            if result.count == limit { break }
        }
        return result
    }

    private func write(_ png: Data, suffix: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH-mm-ss-SSS"
        let suffixPart = suffix.isEmpty ? "" : "-\(suffix)"
        let fileURL = try todayDirectory().appendingPathComponent(
            "CatchIt-\(formatter.string(from: Date()))\(suffixPart).png"
        )
        try png.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func encode(_ cgImage: CGImage) throws -> EncodedImage {
        EncodedImage(
            png: try encode(cgImage, type: "public.png" as CFString),
            tiff: try encode(cgImage, type: "public.tiff" as CFString)
        )
    }

    private func encode(_ cgImage: CGImage, type: CFString) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            throw StoreError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw StoreError.imageEncodingFailed }
        return data as Data
    }

    private func publishToPasteboard(_ encoded: EncodedImage) {
        pasteboard.clearContents()
        _ = pasteboard.setData(encoded.png, forType: .png)
        _ = pasteboard.setData(encoded.tiff, forType: .tiff)
    }

    private static func screenshotFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension.lowercased() == "png",
                  url.lastPathComponent.hasPrefix("CatchIt-") else { return nil }
            return url
        }
    }

    private static func expiredScreenshotFiles(in root: URL, days: Int) -> [URL] {
        let calendar = Calendar(identifier: .gregorian)
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return screenshotFiles(in: root).filter { url in
            guard let date = formatter.date(from: url.deletingLastPathComponent().lastPathComponent) else { return false }
            return date < cutoff
        }
    }
}

private extension NSImage {
    var catchItCGImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
