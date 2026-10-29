import Foundation

// MARK: - Permission manager
//
// Grants are explicit, persisted, and revocable. Defaults are deny:
// with no prompt handler installed (e.g. a headless call), a request
// returns false rather than assuming the user would have said yes.
// A prompt is not a sandbox — the bridges check grants on every call,
// and revocation takes effect immediately on the next call.

public struct ExtV2PermissionRequest: Sendable {
    public let extensionId: String
    public let capability: ExtV2Capability
    public let reason: String
}

public final class ExtV2PermissionManager: @unchecked Sendable {
    private let storage: ExtV2Storage
    private let lock = NSLock()
    private var grants: [String: Set<ExtV2Capability>]

    /// Set by the UI layer to present a real approval prompt. Nil means
    /// "no one can approve right now", which is a denial, not a queue.
    public var promptHandler: (@Sendable (ExtV2PermissionRequest) async -> Bool)?

    public init(storage: ExtV2Storage = ExtV2Storage()) {
        self.storage = storage
        if let data = try? Data(contentsOf: storage.grantsFile),
           let decoded = try? JSONDecoder().decode([String: [ExtV2Capability]].self, from: data) {
            self.grants = decoded.mapValues(Set.init)
        } else {
            self.grants = [:]
        }
    }

    /// Test variant: grants start in memory and any persistence goes
    /// to a unique temporary directory, never the real grants file.
    public init(grants: [String: Set<ExtV2Capability>]) {
        self.storage = ExtV2Storage(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtV2Tests-\(UUID().uuidString)", isDirectory: true))
        self.grants = grants
    }

    public func isGranted(extensionId: String, capability: ExtV2Capability) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return grants[extensionId]?.contains(capability) ?? false
    }

    public func grantedCapabilities(for extensionId: String) -> [ExtV2Capability] {
        lock.lock(); defer { lock.unlock() }
        return Array(grants[extensionId] ?? []).sorted { $0.rawValue < $1.rawValue }
    }

    public func check(extensionId: String, capability: ExtV2Capability) throws {
        guard isGranted(extensionId: extensionId, capability: capability) else {
            throw ExtV2Error.permissionDenied(capability)
        }
    }

    public func request(extensionId: String, capability: ExtV2Capability, reason: String) async -> Bool {
        if isGranted(extensionId: extensionId, capability: capability) { return true }
        guard let handler = promptHandler else { return false }
        let approved = await handler(ExtV2PermissionRequest(extensionId: extensionId, capability: capability, reason: reason))
        if approved { grant(extensionId: extensionId, capability: capability) }
        return approved
    }

    public func grant(extensionId: String, capability: ExtV2Capability) {
        lock.lock()
        grants[extensionId, default: []].insert(capability)
        let snapshot = grants.mapValues(Array.init)
        lock.unlock()
        try? storage.writeAtomically(snapshot, to: storage.grantsFile)
        ExtV2DiagnosticsService.shared.info("Granted \(capability.rawValue)", extensionId: extensionId)
    }

    public func revoke(extensionId: String, capability: ExtV2Capability) {
        lock.lock()
        grants[extensionId]?.remove(capability)
        let snapshot = grants.mapValues(Array.init)
        lock.unlock()
        try? storage.writeAtomically(snapshot, to: storage.grantsFile)
        ExtV2DiagnosticsService.shared.warning("Revoked \(capability.rawValue)", extensionId: extensionId)
    }

    public func revokeAll(for extensionId: String) {
        lock.lock()
        grants.removeValue(forKey: extensionId)
        let snapshot = grants.mapValues(Array.init)
        lock.unlock()
        try? storage.writeAtomically(snapshot, to: storage.grantsFile)
    }
}
