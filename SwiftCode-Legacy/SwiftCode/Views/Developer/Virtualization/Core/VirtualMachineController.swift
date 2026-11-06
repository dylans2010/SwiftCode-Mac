import Foundation

@MainActor
public final class VirtualMachineController: Sendable {
    private let vmID: UUID

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    public func start() async {
        let store = VirtualizationStateStore.shared
        guard let vm = store.virtualMachines.first(where: { $0.id == vmID }) else {
            VirtualizationEventBus.shared.post(.error(vmID, "Environment not found."))
            return
        }

        #if canImport(Virtualization)
        do {
            try await VirtualizationService.shared.startVM(
                id: vmID,
                cpuCores: vm.cpuCores,
                memoryMB: vm.memoryMB,
                imagePath: vm.imagePath
            )
            VirtualizationEventBus.shared.post(.started(vmID))
            VirtualizationRuntime.shared.registerSession(id: vmID)
        } catch {
            VirtualizationEventBus.shared.post(.error(vmID, error.localizedDescription))
        }
        #else
        VirtualizationEventBus.shared.post(.started(vmID))
        VirtualizationRuntime.shared.registerSession(id: vmID)
        #endif
    }

    public func stop() async {
        #if canImport(Virtualization)
        try? await VirtualizationService.shared.stopVM(id: vmID, force: true)
        #endif
        VirtualizationEventBus.shared.post(.stopped(vmID))
        VirtualizationRuntime.shared.removeSession(id: vmID)
    }

    public func pause() async {
        #if canImport(Virtualization)
        try? await VirtualizationService.shared.pauseVM(id: vmID)
        #endif
        VirtualizationEventBus.shared.post(.paused(vmID))
    }

    public func resume() async {
        #if canImport(Virtualization)
        try? await VirtualizationService.shared.resumeVM(id: vmID)
        #endif
        VirtualizationEventBus.shared.post(.resumed(vmID))
    }

    public func restart() async {
        await stop()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await start()
        VirtualizationEventBus.shared.post(.restarted(vmID))
    }

    public func shutdown() async {
        await stop()
    }
}
