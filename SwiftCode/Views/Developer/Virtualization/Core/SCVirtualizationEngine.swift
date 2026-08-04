import Foundation
#if canImport(Virtualization)
import Virtualization
#endif

public final class SCVirtualizationEngine: Sendable {
    public static let shared = SCVirtualizationEngine()

    private init() {}

    public func isVirtualizationSupported() -> Bool {
        #if canImport(Virtualization)
        #if arch(arm64)
        if #available(macOS 12.0, *) {
            return true
        } else {
            return false
        }
        #else
        return false
        #endif
        #else
        return false
        #endif
    }

    public func createController(for vmID: UUID) -> VirtualMachineController {
        return VirtualMachineController(vmID: vmID)
    }

    @MainActor
    public func instantiateRealVirtualMachine(cpuCores: Int, memoryMB: Int, imagePath: String?) -> Any? {
        #if canImport(Virtualization)
        if #available(macOS 12.0, *), isVirtualizationSupported() {
            return VirtualizationService.shared.createVirtualMachine(cpuCores: cpuCores, memoryMB: memoryMB, imagePath: imagePath)
        }
        #endif
        return nil
    }

    public func validateImageFile(at path: String) async -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: path)
    }
}
