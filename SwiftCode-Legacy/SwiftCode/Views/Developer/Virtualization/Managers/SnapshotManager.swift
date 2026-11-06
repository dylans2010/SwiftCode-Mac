import Foundation

public final class VMSnapshotManager: Sendable {
    public static let shared = VMSnapshotManager()

    private init() {}

    public func createSnapshot(for vmID: UUID, name: String, description: String) throws {
        var vms = VirtualMachineRegistry.shared.load()
        if let idx = vms.firstIndex(where: { $0.id == vmID }) {
            let snapshot = VMSnapshot(id: UUID(), name: name, description: description, timestamp: Date())
            vms[idx].snapshots.insert(snapshot, at: 0)
            try VirtualMachineRegistry.shared.save(vms)
            VirtualizationEventBus.shared.post(.metadataUpdated(vmID))
        }
    }

    public func restoreSnapshot(vmID: UUID, snapshotID: UUID) throws {
        // Here we'd perform the raw restore. We will update registry and post the event.
        VirtualizationEventBus.shared.post(.metadataUpdated(vmID))
    }

    public func deleteSnapshot(vmID: UUID, snapshotID: UUID) throws {
        var vms = VirtualMachineRegistry.shared.load()
        if let idx = vms.firstIndex(where: { $0.id == vmID }) {
            vms[idx].snapshots.removeAll { $0.id == snapshotID }
            try VirtualMachineRegistry.shared.save(vms)
            VirtualizationEventBus.shared.post(.metadataUpdated(vmID))
        }
    }

    public func renameSnapshot(vmID: UUID, snapshotID: UUID, newName: String, newDesc: String) throws {
        var vms = VirtualMachineRegistry.shared.load()
        if let idx = vms.firstIndex(where: { $0.id == vmID }) {
            if let snapIdx = vms[idx].snapshots.firstIndex(where: { $0.id == snapshotID }) {
                vms[idx].snapshots[snapIdx].name = newName
                vms[idx].snapshots[snapIdx].description = newDesc
                try VirtualMachineRegistry.shared.save(vms)
                VirtualizationEventBus.shared.post(.metadataUpdated(vmID))
            }
        }
    }
}
