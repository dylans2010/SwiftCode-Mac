import Foundation

public actor SDKDeveloperLogger {
    public static let shared = SDKDeveloperLogger()

    public static let maxFileBytes = 10 * 1024 * 1024
    public static let sdkVersion = "1.0.0"

    private var handle: FileHandle?

    private var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swiftcode/logs/developer-sdk.log", isDirectory: false)
    }

    private init() {}

    public func log(error: SDKError, diagnostics: [String: String]? = nil, context: [String: String]? = nil) {
        let redactedDiagnostics = diagnostics?.mapValues { SDKLogRedaction.redactSecrets($0) }
        let redactedContext = context?.mapValues { SDKLogRedaction.redactSecrets($0) }
        var payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: error.timestamp),
            "correlationId": error.correlationId,
            "code": error.code.rawValue,
            "message": error.message,
            "sdkVersion": Self.sdkVersion,
            "process": [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "name": ProcessInfo.processInfo.processName,
                "thread": Thread.isMainThread ? "main" : "background",
            ],
        ]
        if let redactedDiagnostics { payload["diagnostics"] = redactedDiagnostics }
        if let redactedContext { payload["context"] = redactedContext }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try append(data)
        } catch let writeError {
            SDKLog.error("SDKDeveloperLogger: failed to log \(error.code.rawValue): \(writeError.localizedDescription)",
                         subsystem: "com.swiftcode.sdk", category: "sdk-developer")
        }
    }

    public func fetchEntries(correlationId: String) -> [[String: Any]] {
        let urls = [logURL.appendingPathExtension("2"), logURL.appendingPathExtension("1"), logURL]
        var result: [[String: Any]] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            for line in data.split(separator: 0x0A) {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      object["correlationId"] as? String == correlationId else { continue }
                result.append(object)
            }
        }
        return result
    }

    public func flushAndClose() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
    }

    private func append(_ data: Data) throws {
        try ensureHandle()
        guard let handle else { return }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0A]))
        try rotateIfNeeded()
    }

    private func ensureHandle() throws {
        if handle != nil { return }
        let url = logURL
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        handle = try FileHandle(forWritingTo: url)
        try handle?.seekToEnd()
    }

    private func rotateIfNeeded() throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue >= Self.maxFileBytes else { return }
        try? handle?.close()
        handle = nil
        let one = logURL.appendingPathExtension("1")
        let two = logURL.appendingPathExtension("2")
        try? FileManager.default.removeItem(at: two)
        if FileManager.default.fileExists(atPath: one.path) {
            try? FileManager.default.moveItem(at: one, to: two)
        }
        try? FileManager.default.moveItem(at: logURL, to: one)
        try ensureHandle()
    }
}
