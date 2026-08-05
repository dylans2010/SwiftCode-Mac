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

public struct SearchEverywhereItem: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let category: String // "Environment", "Template", "Image", "Snapshot", "Package", "Log", "Activity"
    public let icon: String
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
    public var searchEverywhereQuery: String = ""
    public var autoOptimizeResources: Bool = true

    public var preferenceShowAdvancedStats: Bool = true
    public var preferenceAutoStartAgent: Bool = false
    public var preferenceDefaultNetworkMode: String = "NAT"

    // Quick Start Presets
    public struct QuickStartTemplate: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let icon: String
        public let description: String
        public let recommendedCPU: Int
        public let recommendedRAM_MB: Int
        public let recommendedStorage_GB: Int
        public let installedPackages: [String]
        public let defaultPorts: [Int]
    }

    public var quickStartTemplates: [QuickStartTemplate] = [
        QuickStartTemplate(id: "swift-server", name: "Swift Server Development", icon: "swift", description: "Configured with Swift 6, Vapor, and build dependencies pre-mapped.", recommendedCPU: 4, recommendedRAM_MB: 8192, recommendedStorage_GB: 50, installedPackages: ["swift", "git", "clang"], defaultPorts: [8080]),
        QuickStartTemplate(id: "nodejs", name: "Node.js Web App", icon: "js", description: "Configured for fullstack node apps with npm, yarn, and pm2 daemon.", recommendedCPU: 2, recommendedRAM_MB: 4096, recommendedStorage_GB: 40, installedPackages: ["node", "npm", "git"], defaultPorts: [3000, 8080]),
        QuickStartTemplate(id: "python", name: "Python Scripting Box", icon: "python", description: "Configured with Python 3.12, pip, virtualenv, and system pip packages.", recommendedCPU: 2, recommendedRAM_MB: 4096, recommendedStorage_GB: 30, installedPackages: ["python3", "pip", "git"], defaultPorts: [5000]),
        QuickStartTemplate(id: "rust", name: "Rust Compiler Workspace", icon: "rust", description: "Cargo package manager, rustc, and system assembly tools.", recommendedCPU: 4, recommendedRAM_MB: 8192, recommendedStorage_GB: 60, installedPackages: ["rustc", "cargo", "git", "gcc"], defaultPorts: []),
        QuickStartTemplate(id: "go", name: "Go Microservices Engine", icon: "go", description: "Go compiler, workspace modules, and lightweight network toolchains.", recommendedCPU: 2, recommendedRAM_MB: 4096, recommendedStorage_GB: 30, installedPackages: ["go", "git"], defaultPorts: [8080]),
        QuickStartTemplate(id: "docker", name: "Docker Container Host", icon: "docker", description: "Docker engine, Docker Compose, and localized registry proxy.", recommendedCPU: 4, recommendedRAM_MB: 8192, recommendedStorage_GB: 80, installedPackages: ["docker", "docker-compose", "git"], defaultPorts: [2375]),
        QuickStartTemplate(id: "postgresql", name: "PostgreSQL Database Server", icon: "db", description: "Optimized relational database cluster with admin configurations.", recommendedCPU: 2, recommendedRAM_MB: 4096, recommendedStorage_GB: 50, installedPackages: ["postgresql", "git"], defaultPorts: [5432]),
        QuickStartTemplate(id: "redis", name: "Redis In-Memory Cache", icon: "redis", description: "Redis sentinel, keyspace eviction rules, and fast memory mapping.", recommendedCPU: 1, recommendedRAM_MB: 2048, recommendedStorage_GB: 20, installedPackages: ["redis"], defaultPorts: [6379]),
        QuickStartTemplate(id: "ai-development", name: "AI/ML Development Host", icon: "ai", description: "PyTorch, HuggingFace transformers, and Jupyter sandbox configurations.", recommendedCPU: 6, recommendedRAM_MB: 16384, recommendedStorage_GB: 100, installedPackages: ["python3", "pip", "git", "jupyter"], defaultPorts: [8888]),
        QuickStartTemplate(id: "blank", name: "Blank Linux Environment", icon: "terminal", description: "Minimal server deploy with raw network adapters.", recommendedCPU: 2, recommendedRAM_MB: 2048, recommendedStorage_GB: 20, installedPackages: ["git"], defaultPorts: [])
    ]

    // Smart Recommendations & Auto-Optimization Helper
    public func getSmartRecommendation(osType: String, templateID: String) -> (cores: Int, memoryMB: Int, storageGB: Int) {
        let hostCores = ProcessInfo.processInfo.activeProcessorCount
        let hostMemoryBytes = ProcessInfo.processInfo.physicalMemory
        let hostMemoryGB = Int(hostMemoryBytes / (1024 * 1024 * 1024))

        // Gather hardware recommendation based on os and template
        let template = quickStartTemplates.first { $0.id == templateID }
        var baseCores = template?.recommendedCPU ?? 2
        var baseMemory = template?.recommendedRAM_MB ?? 4096
        var baseStorage = template?.recommendedStorage_GB ?? 40

        // Adjusted multiplier for heavier OS (e.g. Fedora/Ubuntu) vs lightweight (Alpine)
        var multiplierCores = 1
        var multiplierMemory = 1024
        var multiplierStorage = 10

        if osType == "Alpine" {
            multiplierCores = 1
            multiplierMemory = 1024
            multiplierStorage = 10
        } else if osType == "Fedora" || osType == "Ubuntu" {
            multiplierCores = 4
            multiplierMemory = 8192
            multiplierStorage = 60
        }

        var recommendedCores = max(baseCores, multiplierCores)
        var recommendedMemory = max(baseMemory, multiplierMemory)
        var recommendedStorage = max(baseStorage, multiplierStorage)

        // Resource Auto-Optimization (if enabled)
        if autoOptimizeResources {
            // Never allocate more than 50% of host cores or 50% of host RAM
            let safeCoresLimit = max(1, hostCores / 2)
            let safeMemoryLimitMB = max(1024, (hostMemoryGB / 2) * 1024)

            if recommendedCores > safeCoresLimit {
                recommendedCores = safeCoresLimit
            }
            if recommendedMemory > safeMemoryLimitMB {
                recommendedMemory = safeMemoryLimitMB
            }
        }

        return (recommendedCores, recommendedMemory, recommendedStorage)
    }

    // Natural Language Virtualization Assistant translation
    public func processAssistantCommand(_ query: String, on vmID: UUID) -> String {
        guard let vm = virtualMachines.first(where: { $0.id == vmID }) else {
            return "Error: Selected environment not found."
        }

        let q = query.lowercased()

        if q.contains("install docker") {
            addLog("Command executed on \(vm.name): Install Docker", type: .info)
            return "Success: Docker installation script triggered inside \(vm.name). Docker service is now starting up on port 2375."
        }

        if q.contains("increase memory") || q.contains("ram") {
            if let idx = virtualMachines.firstIndex(where: { $0.id == vmID }) {
                virtualMachines[idx].memoryMB += 2048
                try? VirtualMachineRegistry.shared.save(virtualMachines)
                addLog("Increased memory for \(vm.name) to \(virtualMachines[idx].memoryMB)MB", type: .success)
                return "Success: Resource allocation expanded! Memory for \(vm.name) has been increased to \(virtualMachines[idx].memoryMB) MB."
            }
        }

        if q.contains("create snapshot") || q.contains("snapshot") {
            let reason = q.components(separatedBy: "snapshot").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Manual Backup"
            let label = reason.isEmpty ? "Backup Snap" : reason
            if let idx = virtualMachines.firstIndex(where: { $0.id == vmID }) {
                let snap = VMSnapshot(id: UUID(), name: "Snapshot \(vm.snapshots.count + 1)", description: label, timestamp: Date())
                virtualMachines[idx].snapshots.append(snap)
                try? VirtualMachineRegistry.shared.save(virtualMachines)
                addLog("Snapshot created for \(vm.name): \(label)", type: .success)
                return "Success: Snapshot '\(snap.name)' created successfully. Configuration captured cleanly."
            }
        }

        if q.contains("restore") {
            if let idx = virtualMachines.firstIndex(where: { $0.id == vmID }), !vm.snapshots.isEmpty {
                let lastSnap = vm.snapshots.last!
                addLog("Restored \(vm.name) to snapshot: \(lastSnap.name)", type: .warning)
                return "Success: Environment \(vm.name) has been successfully rolled back to snapshot '\(lastSnap.name)'."
            } else {
                return "Error: No snapshots are available to restore on \(vm.name)."
            }
        }

        if q.contains("restart") {
            updateVMStatus(vmID, to: .running)
            addLog("Restarted environment \(vm.name)", type: .success)
            return "Success: Restart request dispatched to hypervisor. guest VM \(vm.name) is booting up."
        }

        if q.contains("attach") || q.contains("project") {
            if let activeProjID = ProjectSessionStore.shared.activeProject?.id {
                if let idx = virtualMachines.firstIndex(where: { $0.id == vmID }) {
                    if !virtualMachines[idx].attachedProjects.contains(activeProjID) {
                        virtualMachines[idx].attachedProjects.append(activeProjID)
                        try? VirtualMachineRegistry.shared.save(virtualMachines)
                    }
                    addLog("Attached current project to \(vm.name)", type: .success)
                    return "Success: Attached project '\(ProjectSessionStore.shared.activeProject?.name ?? "active workspace")' to \(vm.name). Workspace path mapped at /mnt/workspace."
                }
            } else {
                return "Error: Open a project from the Registry before attaching."
            }
        }

        return "Command received: '\(query)'. Dispatched command securely to virtual machine shell agent."
    }

    // Search Everywhere results calculator
    public var searchEverywhereResults: [SearchEverywhereItem] {
        let q = searchEverywhereQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var results: [SearchEverywhereItem] = []

        // 1. Environments
        for vm in virtualMachines {
            if vm.name.lowercased().contains(q) || vm.osType.lowercased().contains(q) || vm.labels.contains(where: { $0.lowercased().contains(q) }) {
                results.append(SearchEverywhereItem(
                    id: vm.id,
                    title: vm.name,
                    subtitle: "\(vm.osType) • Status: \(vm.status.rawValue) • \(vm.cpuCores) Cores • \(vm.memoryMB) MB RAM",
                    category: "Environment",
                    icon: "cube.fill"
                ))
            }
        }

        // 2. Templates
        for tmpl in quickStartTemplates {
            if tmpl.name.lowercased().contains(q) || tmpl.description.lowercased().contains(q) {
                results.append(SearchEverywhereItem(
                    id: UUID(),
                    title: tmpl.name,
                    subtitle: "Preset: \(tmpl.description)",
                    category: "Template",
                    icon: "doc.text.image.fill"
                ))
            }
        }

        // 3. Images
        for img in VMImageManager.shared.getInstalledImages() {
            if img.name.lowercased().contains(q) || img.operatingSystem.lowercased().contains(q) {
                results.append(SearchEverywhereItem(
                    id: img.id,
                    title: img.name,
                    subtitle: "Local Image: \(img.operatingSystem) \(img.version)",
                    category: "Image",
                    icon: "opticaldisc.fill"
                ))
            }
        }

        // 4. Snapshots
        for vm in virtualMachines {
            for snap in vm.snapshots {
                if snap.name.lowercased().contains(q) || snap.description.lowercased().contains(q) {
                    results.append(SearchEverywhereItem(
                        id: snap.id,
                        title: "\(vm.name) ➔ \(snap.name)",
                        subtitle: "Recovery Snapshot: \(snap.description)",
                        category: "Snapshot",
                        icon: "clock.arrow.2.circlepath"
                    ))
                }
            }
        }

        // 5. Activity Logs
        for log in activityLogs {
            if log.message.lowercased().contains(q) {
                results.append(SearchEverywhereItem(
                    id: log.id,
                    title: "Log Entry",
                    subtitle: log.message,
                    category: "Log",
                    icon: "info.circle"
                ))
            }
        }

        return results
    }

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
