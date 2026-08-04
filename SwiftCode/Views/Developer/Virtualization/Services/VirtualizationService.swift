import Foundation
import OSLog
#if canImport(Virtualization)
import Virtualization
#endif

public final class VirtualizationService: @unchecked Sendable {
    public static let shared = VirtualizationService()
    private static let logger = Logger(subsystem: "com.swiftcode.virtualization", category: "VirtualizationService")

    private init() {}

    #if canImport(Virtualization)
    @MainActor
    public func createRealVMConfiguration(cpuCores: Int, memoryMB: Int, imagePath: String?) -> VZVirtualMachineConfiguration? {
        guard #available(macOS 12.0, *) else {
            Self.logger.warning("Virtualization.framework requires macOS 12.0 or later.")
            return nil
        }

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
            Self.logger.info("Virtualization configuration validated successfully.")
            return config
        } catch {
            Self.logger.error("Virtualization config validation failed. Error context: \(error.localizedDescription)")
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
