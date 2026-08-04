import Foundation
#if canImport(Virtualization)
import Virtualization
#endif

public final class VirtualizationService: @unchecked Sendable {
    public static let shared = VirtualizationService()

    private init() {}

    #if canImport(Virtualization)
    @MainActor
    public func createRealVMConfiguration(cpuCores: Int, memoryMB: Int, imagePath: String?) -> VZVirtualMachineConfiguration? {
        guard #available(macOS 12.0, *) else { return nil }

        let config = VZVirtualMachineConfiguration()
        config.cpuCount = max(VZVirtualMachineConfiguration.minimumAllowedCPUCount, min(VZVirtualMachineConfiguration.maximumAllowedCPUCount, cpuCores))
        config.memorySize = UInt64(memoryMB) * 1024 * 1024

        // Boot loader setup
        if let imagePath = imagePath {
            let imageURL = URL(fileURLWithPath: imagePath)
            let bootloader = VZLinuxBootLoader(kernelURL: imageURL)
            config.bootLoader = bootloader
        }

        // Setup console and serial interfaces
        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        let attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: FileHandle.standardInput,
            fileHandleForWriting: FileHandle.standardOutput
        )
        serial.attachment = attachment
        config.serialPorts = [serial]

        // Validate config
        do {
            try config.validate()
            return config
        } catch {
            print("Virtualization config validation failed: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    public func createVirtualMachine(cpuCores: Int, memoryMB: Int, imagePath: String?) -> VZVirtualMachine? {
        guard #available(macOS 12.0, *) else { return nil }
        guard let config = createRealVMConfiguration(cpuCores: cpuCores, memoryMB: memoryMB, imagePath: imagePath) else { return nil }

        return VZVirtualMachine(configuration: config)
    }
    #endif
}
