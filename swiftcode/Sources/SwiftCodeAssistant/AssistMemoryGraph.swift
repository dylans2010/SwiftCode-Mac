// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Assist/AssistMemoryGraph.swift
//   (Legacy main ab03f681) — verbatim, no adaptations.
//   Staged by migration subagent F2 (unowned-dependency triage) — NOT yet
//   landed in the repo.
//
// Destination: SwiftCodeAssistant/AssistMemoryGraph.swift.
//
// Conforms to `AssistMemoryGraphProtocol`, already on main
// (`SwiftCodeAssistant/AssistModels.swift:535`) with matching members.

import Foundation

// Thread-safe wrapper with NSLock ensuring concurrency safety
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

    // Advanced graph features would go here
    public func storeRelationship(from: String, to: String, type: String) {
        // Implementation
    }
}
