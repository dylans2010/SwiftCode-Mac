import Foundation

public final class VirtualMachineController: Sendable {
    private let vmID: UUID

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    public func start() async {
        VirtualizationEventBus.shared.post(.started(vmID))
        VirtualizationRuntime.shared.registerSession(id: vmID)
    }

    public func stop() async {
        VirtualizationEventBus.shared.post(.stopped(vmID))
        VirtualizationRuntime.shared.removeSession(id: vmID)
    }

    public func pause() async {
        VirtualizationEventBus.shared.post(.paused(vmID))
    }

    public func resume() async {
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
