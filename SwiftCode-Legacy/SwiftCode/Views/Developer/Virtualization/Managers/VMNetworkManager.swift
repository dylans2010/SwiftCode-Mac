import Foundation

public final class VMNetworkManager: Sendable {
    public static let shared = VMNetworkManager()

    private init() {}

    public func addPortForwarding(vmID: UUID, name: String, hostPort: Int, guestPort: Int, protocolType: String) throws {
        var vms = VirtualMachineRegistry.shared.load()
        if let idx = vms.firstIndex(where: { $0.id == vmID }) {
            let rule = VMPortForwarding(id: UUID(), name: name, hostPort: hostPort, guestPort: guestPort, protocolType: protocolType)
            vms[idx].portForwardings.append(rule)
            try VirtualMachineRegistry.shared.save(vms)
            VirtualizationEventBus.shared.post(.metadataUpdated(vmID))
        }
    }

    public func removePortForwarding(vmID: UUID, ruleID: UUID) throws {
        var vms = VirtualMachineRegistry.shared.load()
        if let idx = vms.firstIndex(where: { $0.id == vmID }) {
            vms[idx].portForwardings.removeAll { $0.id == ruleID }
            try VirtualMachineRegistry.shared.save(vms)
            VirtualizationEventBus.shared.post(.metadataUpdated(vmID))
        }
    }
}
