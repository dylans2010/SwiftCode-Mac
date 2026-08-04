import Foundation

public final class VirtualMachineRegistry: Sendable {
    public static let shared = VirtualMachineRegistry()
    private let registryURL: URL

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let swiftCodeFolder = appSupport.appendingPathComponent("SwiftCode", isDirectory: true)
        self.registryURL = swiftCodeFolder.appendingPathComponent("virtualization_registry.json")

        try? fileManager.createDirectory(at: swiftCodeFolder, withIntermediateDirectories: true, attributes: nil)
    }

    public func save(_ vms: [VirtualMachine]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(vms)
        try data.write(to: registryURL, options: .atomic)
        VirtualizationEventBus.shared.post(.registryChanged)
    }

    public func load() -> [VirtualMachine] {
        do {
            let data = try Data(contentsOf: registryURL)
            let decoder = JSONDecoder()
            return try decoder.decode([VirtualMachine].self)
        } catch {
            // Seed defaults on error or first launch
            let defaults = [
                VirtualMachine(
                    name: "Ubuntu Server LTS",
                    osType: "Ubuntu",
                    version: "24.04 LTS",
                    status: .stopped,
                    cpuCores: 4,
                    memoryMB: 8192,
                    storageGB: 64,
                    uptime: 0
                ),
                VirtualMachine(
                    name: "Debian Development Container",
                    osType: "Debian",
                    version: "12 (Bookworm)",
                    status: .stopped,
                    cpuCores: 2,
                    memoryMB: 4096,
                    storageGB: 40,
                    uptime: 0
                ),
                VirtualMachine(
                    name: "Alpine Micro Environment",
                    osType: "Alpine",
                    version: "3.20.0",
                    status: .stopped,
                    cpuCores: 1,
                    memoryMB: 1024,
                    storageGB: 10,
                    uptime: 0
                )
            ]
            try? save(defaults)
            return defaults
        }
    }
}
