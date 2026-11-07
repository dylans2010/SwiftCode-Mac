import Foundation

public final class PreviewDiagnostics: @unchecked Sendable {
    public static let shared = PreviewDiagnostics()
    private let lock = NSLock()
    public private(set) var logs: [(category: String, message: String, timestamp: Date)] = []

    public init() {}

    public func addLog(category: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        logs.append((category: category, message: message, timestamp: Date()))
    }
}
