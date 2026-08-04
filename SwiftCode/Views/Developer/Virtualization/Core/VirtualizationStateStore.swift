import Foundation
import Observation

public struct ActivityLog: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let message: String
    public let type: LogType

    public enum LogType: String, Codable, Sendable {
        case info, success, warning, error
    }
}

@Observable
@MainActor
public final class VirtualizationStateStore {
    public static let shared = VirtualizationStateStore()

    public var virtualMachines: [VirtualMachine] = []
    public var selectedVMID: UUID? = nil
    public var selectedSidebarTab: SidebarTab = .dashboard
    public var showCreateWizard: Bool = false
    public var imageRequiredNotification: String? = nil

    public var activityLogs: [ActivityLog] = []
    public var activeProjectID: UUID? = nil

    public var searchVMQuery: String = ""
    public var preferenceShowAdvancedStats: Bool = true
    public var preferenceAutoStartAgent: Bool = false
    public var preferenceDefaultNetworkMode: String = "NAT"

    public enum SidebarTab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case environments = "Environments"
        case images = "Images"
        case snapshots = "Snapshots"
        case storage = "Storage"
        case networking = "Networking"
        case settings = "Settings"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .dashboard: return "square.grid.2x2"
            case .environments: return "cube.transparent"
            case .images: return "doc.image"
            case .snapshots: return "clock.arrow.2.circlepath"
            case .storage: return "externaldrive"
            case .networking: return "network"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    private init() {
        self.virtualMachines = VirtualMachineRegistry.shared.load()
        addLog("Virtualization Workspace initialized.", type: .info)

        // Listen to event bus
        VirtualizationEventBus.shared.subscribe { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: VirtualizationEvent) {
        switch event {
        case .started(let id):
            updateVMStatus(id, to: .running)
            addLog("VM \(id) started.", type: .success)
        case .stopped(let id):
            updateVMStatus(id, to: .stopped)
            addLog("VM \(id) stopped.", type: .info)
        case .paused(let id):
            updateVMStatus(id, to: .paused)
            addLog("VM \(id) paused.", type: .info)
        case .resumed(let id):
            updateVMStatus(id, to: .running)
            addLog("VM \(id) resumed.", type: .success)
        case .restarted(let id):
            updateVMStatus(id, to: .running)
            addLog("VM \(id) restarted.", type: .success)
        case .error(let id, let msg):
            updateVMStatus(id, to: .error)
            addLog("VM \(id) error: \(msg)", type: .error)
        case .log(let id, let text):
            // Can be used for live streams
            break
        case .statUpdate:
            break
        case .metadataUpdated(let id):
            refreshVM(id)
        case .registryChanged:
            self.virtualMachines = VirtualMachineRegistry.shared.load()
        }
    }

    public func addLog(_ message: String, type: ActivityLog.LogType = .info) {
        let newLog = ActivityLog(id: UUID(), timestamp: Date(), message: message, type: type)
        activityLogs.insert(newLog, at: 0)
        if activityLogs.count > 100 {
            activityLogs.removeLast()
        }
    }

    public func updateVMStatus(_ id: UUID, to status: VMStatus) {
        if let idx = virtualMachines.firstIndex(where: { $0.id == id }) {
            virtualMachines[idx].status = status
            if status == .stopped {
                virtualMachines[idx].uptime = 0
            }
            try? VirtualMachineRegistry.shared.save(virtualMachines)
        }
    }

    public func refreshVM(_ id: UUID) {
        self.virtualMachines = VirtualMachineRegistry.shared.load()
    }

    public func createVM(name: String, osType: String, version: String, cpu: Int, ramMB: Int, diskGB: Int, imagePath: String?) -> VirtualMachine {
        let newVM = VirtualMachine(
            name: name,
            osType: osType,
            version: version,
            status: .stopped,
            cpuCores: cpu,
            memoryMB: ramMB,
            storageGB: diskGB,
            imagePath: imagePath
        )
        virtualMachines.append(newVM)
        try? VirtualMachineRegistry.shared.save(virtualMachines)
        addLog("Virtual Machine '\(name)' created successfully.", type: .success)
        return newVM
    }

    public func deleteVM(id: UUID) {
        virtualMachines.removeAll { $0.id == id }
        try? VirtualMachineRegistry.shared.save(virtualMachines)
        addLog("Virtual Machine deleted.", type: .warning)
        if selectedVMID == id {
            selectedVMID = nil
        }
    }
}
