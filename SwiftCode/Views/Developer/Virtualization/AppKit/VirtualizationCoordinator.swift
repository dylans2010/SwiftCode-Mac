import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
public final class VirtualizationCoordinator {
    public static let shared = VirtualizationCoordinator()

    public var selectedVMID: UUID? = nil
    public var sidebarTab: VirtualizationStateStore.SidebarTab = .dashboard

    // Terminal live output buffer per VM
    public var terminalSessions: [UUID: [String]] = [:]

    private init() {
        // Listen to event bus log updates
        VirtualizationEventBus.shared.subscribe { [weak self] event in
            if case .log(let vmID, let line) = event {
                Task { @MainActor in
                    var currentLogs = self?.terminalSessions[vmID] ?? []
                    currentLogs.append(line)
                    if currentLogs.count > 1000 {
                        currentLogs.removeFirst()
                    }
                    self?.terminalSessions[vmID] = currentLogs
                }
            }
        }
    }

    public func appendTerminalLine(vmID: UUID, line: String) {
        var logs = terminalSessions[vmID] ?? []
        logs.append(line)
        if logs.count > 1000 {
            logs.removeFirst()
        }
        terminalSessions[vmID] = logs
        // Post event
        VirtualizationEventBus.shared.post(.log(vmID, line))
    }
}
