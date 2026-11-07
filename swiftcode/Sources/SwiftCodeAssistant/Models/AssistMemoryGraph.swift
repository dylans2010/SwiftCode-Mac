import Foundation

public final class AssistMemoryGraph: @unchecked Sendable, AssistMemoryGraphProtocol {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func store(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }

    public func retrieve(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }

    public func storeRelationship(from: String, to: String, type: String) {
    }
}
