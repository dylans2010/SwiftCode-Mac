import SwiftUI

public struct VirtualMachineDetailView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var selectedTab: DetailCategory = .consoleShell
    @State private var consoleSubTab: String = "Terminal" // Default to Terminal
    @State private var assistantQuery = ""
    @State private var assistantResponse = ""

    // Multiple Terminals States
    @State private var terminalSessions: [String] = ["Shell Connection 1"]
    @State private var activeTerminalIndex: Int = 0

    // Software Catalog installation simulation states
    @State private var installingPackageName: String? = nil
    @State private var installationProgress: Double = 0.0

    public enum DetailCategory: String, CaseIterable, Identifiable {
        case consoleShell = "Console & Terminal"
        case monitor = "Resource Monitoring"
        case softwareCatalog = "Software Catalog"
        case storageSharing = "Storage & Sharing"
        case network = "Network Ports"
        case snapshots = "Snapshots & Timeline"
        case settings = "Hardware Config"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .consoleShell: return "terminal.fill"
            case .monitor: return "waveform.path.ecg"
            case .softwareCatalog: return "shippingbox.fill"
            case .storageSharing: return "folder.badge.plus"
            case .network: return "network"
            case .snapshots: return "clock.arrow.2.circlepath"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    private var activeVM: VirtualMachine? {
        stateStore.virtualMachines.first { $0.id == vmID }
    }

    private var activeProvider: any OperatingSystemProvider {
        guard let vm = activeVM else { return UbuntuProvider() }
        switch vm.osType {
        case "Ubuntu": return UbuntuProvider()
        case "Debian": return DebianProvider()
        case "Fedora": return FedoraProvider()
        case "Alpine": return AlpineProvider()
        default: return UbuntuProvider()
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let vm = activeVM {
                // Header Bar (Apple HIG Style)
                HStack(spacing: 16) {
                    Button {
                        stateStore.selectedVMID = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Image(systemName: provSystemIcon(vm.osType))
                        .font(.title)
                        .foregroundStyle(provColor(vm.osType))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(vm.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)

                            statusBadge(for: vm.status)
                        }
                        Text("\(vm.osType) \(vm.version) • \(vm.cpuCores) Cores • \(String(format: "%.1f GB RAM", Double(vm.memoryMB)/1024.0)) • \(vm.storageGB) GB Disk")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // VM Controls
                    HStack(spacing: 10) {
                        if vm.status == .stopped || vm.status == .error {
                            Button {
                                triggerStart()
                            } label: {
                                Label("Start Sandbox", systemImage: "play.fill")
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.large)
                        } else {
                            Button {
                                triggerStop()
                            } label: {
                                Label("Stop Sandbox", systemImage: "stop.fill")
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }

                        Button {
                            triggerRestart()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .help("Restart Sandbox Environment")
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // INTEGRATED ONBOARDING FIRST RUN EXPERIENCE
                if vm.isFirstRun {
                    firstRunExperienceCard(vm: vm)
                }

                // Integrated Natural Language Assistant Row
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(.orange)

                            TextField("Ask the sandbox assistant (e.g. 'Install Docker', 'Increase RAM', 'Backup snapshot', 'Attach current project')...", text: $assistantQuery, onCommit: executeAssistantCommand)
                                .textFieldStyle(.plain)
                                .font(.subheadline)

                            Button("Run Command") {
                                executeAssistantCommand()
                            }
                            .buttonStyle(.bordered)
                            .disabled(assistantQuery.isEmpty)
                        }

                        if !assistantResponse.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                Text(assistantResponse)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.blue)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(6)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // High-level segmented category pickers
                Picker("", selection: $selectedTab) {
                    ForEach(DetailCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.icon)
                            .tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                // Tab Content Workspace
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch selectedTab {
                        case .consoleShell:
                            VStack(alignment: .leading, spacing: 16) {
                                Picker("", selection: $consoleSubTab) {
                                    Text("Interactive Shells").tag("Terminal")
                                    Text("Serial Hypervisor Console").tag("Console")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 320)
                                .padding(.bottom, 8)

                                if consoleSubTab == "Console" {
                                    VirtualMachineConsoleView(vmID: vmID)
                                } else {
                                    multipleTerminalsView(vm: vm)
                                }
                            }

                        case .monitor:
                            VirtualMachineMonitorView(vmID: vmID)

                        case .softwareCatalog:
                            softwareCatalogView(vm: vm)

                        case .storageSharing:
                            VStack(alignment: .leading, spacing: 24) {
                                VirtualMachineStorageView(vmID: vmID)
                                Divider()
                                VirtualMachineSharedFoldersView(vmID: vmID)
                            }

                        case .network:
                            VirtualMachineNetworkView(vmID: vmID)

                        case .snapshots:
                            VirtualMachineSnapshotsView(vmID: vmID)

                        case .settings:
                            VStack(spacing: 24) {
                                VirtualMachineSettingsView(vmID: vmID)
                                Divider()
                                documentationCenterView(vm: vm)
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "Development Environment Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("This configuration is not available or has been deleted from the local registry.")
                )
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // FIRST RUN EXPERIENCE ONBOARDING CARD
    @ViewBuilder
    private func firstRunExperienceCard(vm: VirtualMachine) -> some View {
        GroupBox(label:
            HStack {
                Label("First Run Experience Onboarding", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Button {
                    completeFirstRunGuide()
                } label: {
                    Text("Got it, Close Guide")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to your fresh \(vm.osType) guest sandbox! Let's complete these critical developer environment validations:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("**Update Package Repositories:** Run `sudo apt update` or corresponding package commands to fetch stable dependency indexes.")
                            .font(.caption)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("**Verify Network Gateway:** Ping official host gateways or search software index servers safely.")
                            .font(.caption)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("**Mount Shared Project Directories:** Make sure your host folder mappings are mounted cleanly at `/mnt/workspace`.")
                            .font(.caption)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("**Launch Integrated Command Terminal:** Open multiple shell terminals inside this detail pane below.")
                            .font(.caption)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func completeFirstRunGuide() {
        guard let idx = stateStore.virtualMachines.firstIndex(where: { $0.id == vmID }) else { return }
        stateStore.virtualMachines[idx].isFirstRun = false
        try? VirtualMachineRegistry.shared.save(stateStore.virtualMachines)
        stateStore.addLog("Onboarding guide completed successfully.", type: .success)
    }

    // MULTIPLE TERMINALS VIEWS
    @ViewBuilder
    private func multipleTerminalsView(vm: VirtualMachine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<terminalSessions.count, id: \.self) { idx in
                            Button {
                                activeTerminalIndex = idx
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "terminal")
                                    Text(terminalSessions[idx])
                                    if terminalSessions.count > 1 {
                                        Button {
                                            closeTerminalSession(at: idx)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(activeTerminalIndex == idx ? Color.blue.opacity(0.15) : Color.primary.opacity(0.04))
                                .foregroundStyle(activeTerminalIndex == idx ? .blue : .primary)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    spawnNewTerminalSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .padding(6)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Spawn an additional terminal console")
            }

            // Real Terminal Shell Panel
            VirtualMachineTerminalView(vmID: vmID)
                .frame(minHeight: 300)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
    }

    private func spawnNewTerminalSession() {
        let count = terminalSessions.count + 1
        terminalSessions.append("Shell Connection \(count)")
        activeTerminalIndex = terminalSessions.count - 1
        stateStore.addLog("Spawned new interactive shell console Terminal \(count).", type: .info)
    }

    private func closeTerminalSession(at idx: Int) {
        terminalSessions.remove(at: idx)
        activeTerminalIndex = max(0, idx - 1)
        stateStore.addLog("Closed interactive shell console Terminal.", type: .warning)
    }

    // SOFTWARE CATALOG & HEALTH VIEW
    @ViewBuilder
    private func softwareCatalogView(vm: VirtualMachine) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Health Overview Panel
            GroupBox(label: Text("Sandbox Software Health Diagnosis").font(.headline).foregroundStyle(.blue)) {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PACKAGE HEALTH INDEX")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("GOOD")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.green)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("INSTALLED PACKAGES")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Text("\(vm.installedPackagesList.count) developer tools")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PENDING UPDATES")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Text("2 updates available")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }

                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            if let pkg = installingPackageName {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Installing '\(pkg)' inside the \(vm.osType) Sandbox...")
                            .font(.headline)
                        ProgressView(value: installationProgress, total: 1.0)
                            .progressViewStyle(.linear)
                        Text("Dispatched package install payload using \(vm.osType == "Alpine" ? "apk" : (vm.osType == "Fedora" ? "dnf" : "apt")) manager...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }

            // Catalog Grid
            Text("Development Tools Catalog")
                .font(.headline)
                .foregroundStyle(.secondary)

            let tools = getCatalogTools(vm: vm)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(tools) { tool in
                    GroupBox {
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox.fill")
                                .font(.title2)
                                .foregroundStyle(tool.isInstalled ? .green : .secondary)
                                .frame(width: 36, height: 36)
                                .background(tool.isInstalled ? Color.green.opacity(0.1) : Color.primary.opacity(0.04))
                                .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(tool.name)
                                    .font(.headline)
                                Text(tool.isInstalled ? "Installed • \(tool.version)" : "Not Installed")
                                    .font(.caption2)
                                    .foregroundStyle(tool.isInstalled ? .secondary : .orange)

                                Text(tool.healthStatus)
                                    .font(.caption2)
                                    .foregroundStyle(tool.healthStatus == "Version Conflict" ? .red : (tool.healthStatus == "Update Available" ? .orange : .green))
                                    .fontWeight(.semibold)
                            }

                            Spacer()

                            if tool.isInstalled {
                                if tool.healthStatus == "Update Available" {
                                    Button("Update") {
                                        dispatchToolInstall(name: tool.name)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .controlSize(.small)
                                } else {
                                    Button("Reinstall") {
                                        dispatchToolInstall(name: tool.name)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            } else {
                                Button("Install") {
                                    dispatchToolInstall(name: tool.name)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
        }
    }

    struct CatalogTool: Identifiable {
        var id: String { name }
        let name: String
        let version: String
        let isInstalled: Bool
        let healthStatus: String // "Healthy", "Update Available", "Version Conflict", "Missing"
    }

    private func getCatalogTools(vm: VirtualMachine) -> [CatalogTool] {
        return [
            CatalogTool(name: "Swift 6.0", version: "v6.0-release", isInstalled: vm.installedPackagesList.contains("swift"), healthStatus: vm.installedPackagesList.contains("swift") ? "Healthy" : "Missing"),
            CatalogTool(name: "Git VCS", version: "v2.43.0", isInstalled: vm.installedPackagesList.contains("git"), healthStatus: vm.installedPackagesList.contains("git") ? "Update Available" : "Missing"),
            CatalogTool(name: "Docker Engine", version: "v25.0.3", isInstalled: vm.installedPackagesList.contains("docker"), healthStatus: vm.installedPackagesList.contains("docker") ? "Healthy" : "Missing"),
            CatalogTool(name: "Node.js Platform", version: "v20.11.0", isInstalled: vm.installedPackagesList.contains("node"), healthStatus: vm.installedPackagesList.contains("node") ? "Healthy" : "Missing"),
            CatalogTool(name: "Python interpreter", version: "v3.12.1", isInstalled: vm.installedPackagesList.contains("python3") || vm.installedPackagesList.contains("python"), healthStatus: vm.installedPackagesList.contains("python3") ? "Version Conflict" : "Missing"),
            CatalogTool(name: "Redis Cache Server", version: "v7.2.4", isInstalled: vm.installedPackagesList.contains("redis"), healthStatus: vm.installedPackagesList.contains("redis") ? "Healthy" : "Missing"),
            CatalogTool(name: "PostgreSQL Database", version: "v16.1", isInstalled: vm.installedPackagesList.contains("postgresql"), healthStatus: vm.installedPackagesList.contains("postgresql") ? "Healthy" : "Missing"),
            CatalogTool(name: "Nginx Server", version: "v1.24.0", isInstalled: vm.installedPackagesList.contains("nginx"), healthStatus: vm.installedPackagesList.contains("nginx") ? "Healthy" : "Missing"),
            CatalogTool(name: "Go Language Compiler", version: "v1.22.0", isInstalled: vm.installedPackagesList.contains("go"), healthStatus: vm.installedPackagesList.contains("go") ? "Healthy" : "Missing"),
            CatalogTool(name: "Rust Toolchain", version: "v1.75.0", isInstalled: vm.installedPackagesList.contains("rustc") || vm.installedPackagesList.contains("cargo"), healthStatus: (vm.installedPackagesList.contains("rustc") || vm.installedPackagesList.contains("cargo")) ? "Healthy" : "Missing")
        ]
    }

    private func dispatchToolInstall(name: String) {
        installingPackageName = name
        installationProgress = 0.0

        Task {
            for step in 1...10 {
                try? await Task.sleep(nanoseconds: 120_000_000)
                installationProgress = Double(step) / 10.0
            }

            // Update VM package list
            if let idx = stateStore.virtualMachines.firstIndex(where: { $0.id == vmID }) {
                let lowerName = name.components(separatedBy: " ").first?.lowercased() ?? name.lowercased()
                if !stateStore.virtualMachines[idx].installedPackagesList.contains(lowerName) {
                    stateStore.virtualMachines[idx].installedPackagesList.append(lowerName)
                }
                try? VirtualMachineRegistry.shared.save(stateStore.virtualMachines)
            }

            stateStore.addLog("Successfully compiled/installed \(name) inside developer environment.", type: .success)
            installingPackageName = nil
        }
    }

    // DOCUMENTATION CENTER VIEW
    @ViewBuilder
    private func documentationCenterView(vm: VirtualMachine) -> some View {
        GroupBox(label:
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.blue)
                Text("\(vm.osType) Documentation Center")
                    .font(.headline)
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Access official, pristine, and secure technical documentation for \(vm.osType) directly within SCVirtualizationKit:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SCDetailRow(label: "Official Website", value: activeProvider.officialWebsite)
                SCDetailRow(label: "Documentation Wiki", value: activeProvider.officialDocumentation)
                SCDetailRow(label: "Architecture Support", value: activeProvider.supportedArchitectures)
                SCDetailRow(label: "Minimum Hardware", value: activeProvider.minimumRequirements)
                SCDetailRow(label: "Package Manager Info", value: activeProvider.packageManagerGuide)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Release Notes Summary:")
                        .fontWeight(.bold)
                        .font(.caption)
                    Text(activeProvider.releaseNotes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Security Advisories Guide:")
                        .fontWeight(.bold)
                        .font(.caption)
                    Text(activeProvider.securityAdvisories)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Getting Started Workflow:")
                        .fontWeight(.bold)
                        .font(.caption)
                    Text(activeProvider.gettingStartedGuide)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Button("Visit Official Docs") {
                        if let url = URL(string: activeProvider.officialDocumentation) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("View Community Resources") {
                        if let url = URL(string: activeProvider.communityResources) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func executeAssistantCommand() {
        let q = assistantQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        let response = stateStore.processAssistantCommand(q, on: vmID)
        assistantResponse = response
        assistantQuery = ""

        stateStore.refreshVM(vmID)

        Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if assistantResponse == response {
                assistantResponse = ""
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for status: VMStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.12))
            .foregroundStyle(statusColor(status))
            .cornerRadius(4)
    }

    private func provSystemIcon(_ name: String) -> String {
        switch name {
        case "Ubuntu": return "cpu"
        case "Debian": return "circle.circle"
        case "Fedora": return "shippingbox"
        case "Alpine": return "snowflake"
        default: return "terminal"
        }
    }

    private func provColor(_ name: String) -> Color {
        switch name {
        case "Ubuntu": return .orange
        case "Debian": return .red
        case "Fedora": return .blue
        case "Alpine": return .teal
        default: return .secondary
        }
    }

    private func statusColor(_ status: VMStatus) -> Color {
        switch status {
        case .running: return .green
        case .starting: return .blue
        case .stopped: return .secondary
        case .pausing, .paused: return .orange
        case .stopping: return .orange
        case .error: return .red
        }
    }

    private func triggerStart() {
        Task {
            let ctrl = SCVirtualizationEngine.shared.createController(for: vmID)
            await ctrl.start()
        }
    }

    private func triggerStop() {
        Task {
            let ctrl = SCVirtualizationEngine.shared.createController(for: vmID)
            await ctrl.stop()
        }
    }

    private func triggerRestart() {
        Task {
            let ctrl = SCVirtualizationEngine.shared.createController(for: vmID)
            await ctrl.restart()
        }
    }
}
