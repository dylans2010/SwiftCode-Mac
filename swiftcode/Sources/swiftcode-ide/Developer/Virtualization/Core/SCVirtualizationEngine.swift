// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/Virtualization/Core/SCVirtualizationEngine.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
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

    @MainActor
    public func createController(for vmID: UUID) -> VirtualMachineController {
        return VirtualMachineController(vmID: vmID)
    }

    @MainActor
    public func instantiateRealVirtualMachine(cpuCores: Int, memoryMB: Int, imagePath: String?) -> Any? {
        #if canImport(Virtualization)
        if #available(macOS 12.0, *), isVirtualizationSupported() {
            let tempID = UUID()
            if let config = try? VirtualizationService.shared.createRealVMConfiguration(cpuCores: cpuCores, memoryMB: memoryMB, imagePath: imagePath, vmID: tempID) {
                return VZVirtualMachine(configuration: config)
            }
        }
        #endif
        return nil
    }

    public func validateImageFile(at path: String) async -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: path)
    }
}
