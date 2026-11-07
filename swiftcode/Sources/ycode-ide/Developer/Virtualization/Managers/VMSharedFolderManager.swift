import Foundation

public final class VMSharedFolderManager: Sendable {
    public static let shared = VMSharedFolderManager()

    private init() {}

    public func addSharedFolder(vmID: UUID, name: String, hostPath: String, guestMountPoint: String, isReadOnly: Bool) throws {
        var vms = VirtualMachineRegistry.shared.load()
        if let idx = vms.firstIndex(where: { $0.id == vmID }) {
            let folder = VMSharedFolder(id: UUID(), name: name, hostPath: hostPath, guestMountPoint: guestMountPoint, isReadOnly: isReadOnly)
            vms[idx].sharedFolders.append(folder)
            try VirtualMachineRegistry.shared.save(vms)
            VirtualizationEventBus.shared.post(.metadataUpdated(vmID))
        }
    }

    public func removeSharedFolder(vmID: UUID, folderID: UUID) throws {
        var vms = VirtualMachineRegistry.shared.load()
        if let idx = vms.firstIndex(where: { $0.id == vmID }) {
            vms[idx].sharedFolders.removeAll { $0.id == folderID }
            try VirtualMachineRegistry.shared.save(vms)
            VirtualizationEventBus.shared.post(.metadataUpdated(vmID))
        }
    }
}
