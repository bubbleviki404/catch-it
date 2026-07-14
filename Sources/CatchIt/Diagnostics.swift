import Foundation

enum Diagnostics {
    static let logURL: URL = {
        let isApp = Bundle.main.bundleIdentifier == "com.gaplab.catchit"
        let fileName = isApp ? "CatchIt.log" : "CatchIt-tests.log"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(fileName)")
    }()

    static func reset() {
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data().write(to: logURL)
        log("CatchIt started (pid: \(ProcessInfo.processInfo.processIdentifier))")
    }

    static func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try? data.write(to: logURL, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch { }
    }
}
