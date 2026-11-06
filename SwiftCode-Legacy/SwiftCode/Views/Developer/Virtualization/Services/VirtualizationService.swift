import Foundation
import OSLog
#if canImport(Virtualization)
import Virtualization
#endif

public final class VirtualizationService: @unchecked Sendable {
    public static let shared = VirtualizationService()
    private static let logger = Logger(subsystem: "com.swiftcode.virtualization", category: "VirtualizationService")

    #if canImport(Virtualization)
    @MainActor
    private var activeVMs: [UUID: VZVirtualMachine] = [:]
    #endif

    private init() {}

    #if canImport(Virtualization)
    @MainActor
    public func getActiveVM(for id: UUID) -> VZVirtualMachine? {
        return activeVMs[id]
    }

    @MainActor
    public func validateISO(at url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw NSError(domain: "VirtualizationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "ISO file does not exist at specified path: \(url.path)"])
        }
        let ext = url.pathExtension.lowercased()
        guard ext == "iso" || ext == "img" || ext == "dmg" else {
            throw NSError(domain: "VirtualizationService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported image format '.\(ext)'. Please import a valid bootable CD-ROM .iso or disk .img file."])
        }
        do {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? UInt64 ?? 0
            if size < 1024 * 1024 { // Less than 1MB
                throw NSError(domain: "VirtualizationService", code: 3, userInfo: [NSLocalizedDescriptionKey: "The specified ISO file is too small (\(size) bytes) and does not appear to be a valid bootable operating system installation image."])
            }
        } catch {
            throw error
        }
    }

    @MainActor
    public func createRealVMConfiguration(cpuCores: Int, memoryMB: Int, imagePath: String?, vmID: UUID) throws -> VZVirtualMachineConfiguration {
        guard #available(macOS 12.0, *) else {
            throw NSError(domain: "VirtualizationService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Virtualization.framework requires macOS 12.0 or later."])
        }

        let config = VZVirtualMachineConfiguration()
        config.cpuCount = max(VZVirtualMachineConfiguration.minimumAllowedCPUCount, min(VZVirtualMachineConfiguration.maximumAllowedCPUCount, cpuCores))
        config.memorySize = UInt64(memoryMB) * 1024 * 1024

        // Boot Loader Configuration
        // Use modern EFI Boot Loader to allow booting off standard installer ISO images
        let bootloader = VZEFIBootLoader()
        // Save EFI variables store inside a standard sandbox cache location to survive restarts
        let cacheDirs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        if let cacheURL = cacheDirs.first {
            let varStoreURL = cacheURL.appendingPathComponent("EFI_VARS_\(vmID).bin")
            if !FileManager.default.fileExists(atPath: varStoreURL.path) {
                // Create blank EFI variable store
                _ = try? VZEFIVariableStore(creatingVariableStoreAt: varStoreURL)
            }
            if let varStore = try? VZEFIVariableStore(url: varStoreURL) {
                bootloader.variableStore = varStore
            }
        }
        config.bootLoader = bootloader

        // Storage Devices Configuration (Virtio Block Devices)
        var devices: [VZStorageDeviceConfiguration] = []

        // 1. Create a primary writable disk image (simulated hard drive for OS install)
        if let cacheURL = cacheDirs.first {
            let primaryDiskURL = cacheURL.appendingPathComponent("DISK_DRIVE_\(vmID).img")
            if !FileManager.default.fileExists(atPath: primaryDiskURL.path) {
                // Create a 20GB sparse disk image if it doesn't exist
                let fd = open(primaryDiskURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
                if fd != -1 {
                    ftruncate(fd, 20 * 1024 * 1024 * 1024)
                    close(fd)
                }
            }
            let mainAttachment = try VZDiskImageStorageDeviceAttachment(url: primaryDiskURL, readOnly: false)
            let mainDisk = VZVirtioBlockDeviceConfiguration(attachment: mainAttachment)
            devices.append(mainDisk)
        }

        // 2. Attach the bootable installer CD-ROM ISO if supplied
        if let imagePath = imagePath, !imagePath.isEmpty {
            let isoURL = URL(fileURLWithPath: imagePath)
            try validateISO(at: isoURL)
            let isoAttachment = try VZDiskImageStorageDeviceAttachment(url: isoURL, readOnly: true)
            let cdromDevice = VZVirtioBlockDeviceConfiguration(attachment: isoAttachment)
            devices.append(cdromDevice)
        }

        config.storageDevices = devices

        // Graphics Devices Configuration (Virtio GPU for display output)
        let graphicsConfig = VZVirtioGraphicsDeviceConfiguration()
        let displayConfig = VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1024, heightInPixels: 768)
        graphicsConfig.scanouts = [displayConfig]
        config.graphicsDevices = [graphicsConfig]

        // Control Devices Configuration (USB Keyboard/Mouse capture)
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        config.keyboards = [VZUSBKeyboardConfiguration()]

        // Entropy Device
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        // Network NAT adapter setup
        let networkConfig = VZVirtioNetworkDeviceConfiguration()
        networkConfig.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [networkConfig]

        // Setup console and serial interfaces
        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        serial.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: FileHandle.standardInput,
            fileHandleForWriting: FileHandle.standardOutput
        )
        config.serialPorts = [serial]

        // Validate config
        try config.validate()
        Self.logger.info("Virtualization configuration validated successfully.")
        return config
    }

    @MainActor
    public func startVM(id: UUID, cpuCores: Int, memoryMB: Int, imagePath: String?) async throws {
        guard #available(macOS 12.0, *) else { return }

        // Terminate any previous instance
        if let existing = activeVMs[id] {
            try? await stopVM(id: id, force: true)
        }

        let config = try createRealVMConfiguration(cpuCores: cpuCores, memoryMB: memoryMB, imagePath: imagePath, vmID: id)
        let vm = VZVirtualMachine(configuration: config)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            vm.start { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        activeVMs[id] = vm
        Self.logger.info("Real Virtualization.framework VM started successfully.")
    }

    @MainActor
    public func stopVM(id: UUID, force: Bool = false) async throws {
        guard #available(macOS 12.0, *) else { return }
        guard let vm = activeVMs[id] else { return }

        if force {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                vm.stop { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } else {
            try vm.requestStop()
        }
        activeVMs.removeValue(forKey: id)
        Self.logger.info("Real Virtualization.framework VM stopped successfully.")
    }

    @MainActor
    public func pauseVM(id: UUID) async throws {
        guard #available(macOS 12.0, *) else { return }
        guard let vm = activeVMs[id] else { return }
        try await vm.pause()
    }

    @MainActor
    public func resumeVM(id: UUID) async throws {
        guard #available(macOS 12.0, *) else { return }
        guard let vm = activeVMs[id] else { return }
        try await vm.resume()
    }
    #endif
}
