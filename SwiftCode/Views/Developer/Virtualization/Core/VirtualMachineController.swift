import Foundation

public final class VirtualMachineController: Sendable {
    private let vmID: UUID

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    public func start() async {
        VirtualizationEventBus.shared.post(.started(vmID))

        // Start simulated stats update stream
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let cpu = Double.random(in: 2.0...35.0)
            let ram = Double.random(in: 15.0...40.0) // percentage
            let net = Double.random(in: 0.1...15.5) // MB/s
            let disk = Double.random(in: 0.0...2.2) // MB/s
            VirtualizationEventBus.shared.post(.statUpdate(self.vmID, cpu, ram, net, disk))
        }
        RunLoop.main.add(timer, forMode: .common)

        VirtualizationRuntime.shared.registerSession(id: vmID, statsTimer: timer)
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
