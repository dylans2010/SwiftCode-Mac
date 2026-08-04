import Foundation

public final class VMBackupManager: Sendable {
    public static let shared = VMBackupManager()

    private init() {}

    public func exportConfiguration(for vm: VirtualMachine, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(vm)
        try data.write(to: url)
    }

    public func importConfiguration(from url: URL) throws -> VirtualMachine {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        var importedVM = try decoder.decode(VirtualMachine.self)

        // Ensure imported VM gets added cleanly with a new unique identity if needed, or keeping it
        let cleanVM = VirtualMachine(
            id: UUID(), // new unique id to avoid collisions
            name: "\(importedVM.name) (Imported)",
            osType: importedVM.osType,
            version: importedVM.version,
            status: .stopped,
            cpuCores: importedVM.cpuCores,
            memoryMB: importedVM.memoryMB,
            storageGB: importedVM.storageGB,
            macAddress: importedVM.macAddress,
            ipAddress: importedVM.ipAddress,
            uptime: 0,
            imagePath: importedVM.imagePath,
            sharedFolders: importedVM.sharedFolders,
            portForwardings: importedVM.portForwardings,
            snapshots: importedVM.snapshots
        )

        var currentVMs = VirtualMachineRegistry.shared.load()
        currentVMs.append(cleanVM)
        try VirtualMachineRegistry.shared.save(currentVMs)

        return cleanVM
    }
}
