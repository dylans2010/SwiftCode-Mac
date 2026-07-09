import Foundation

/// Central registry for component capabilities.
public actor CapabilityRegistry: KernelService {
    public let id = "com.swiftcode.kernel.capabilities"

    private var capabilities: [String: Set<String>] = [:]

    public init() {}

    public func initialize() async throws {
        print("[Capabilities] Capability Registry initialized.")
    }

    public func registerCapability(_ capabilityName: String, for componentId: String) {
        var existing = capabilities[componentId] ?? []
        existing.insert(capabilityName)
        capabilities[componentId] = existing
    }

    public func hasCapability(_ capabilityName: String, for componentId: String) -> Bool {
        return capabilities[componentId]?.contains(capabilityName) ?? false
    }

    public func findComponents(withCapability name: String) -> [String] {
        return capabilities.filter { $0.value.contains(name) }.map { $0.key }
    }
}
