import SwiftUI

public struct VirtualMachineDetailView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var selectedTab: DetailCategory = .consoleShell
    @State private var consoleSubTab: String = "Console" // Console vs Terminal
    @State private var assistantQuery = ""
    @State private var assistantResponse = ""

    public enum DetailCategory: String, CaseIterable, Identifiable {
        case consoleShell = "Console & Terminal"
        case monitor = "Resource Monitoring"
        case storageSharing = "Storage & Sharing"
        case network = "Network Ports"
        case snapshots = "Snapshots & Timeline"
        case settings = "Hardware Config"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .consoleShell: return "terminal.fill"
            case .monitor: return "waveform.path.ecg"
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

                    Image(systemName: "cube.fill")
                        .font(.title)
                        .foregroundStyle(statusColor(vm.status))

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
                                    Text("Live Serial Console").tag("Console")
                                    Text("Interactive Command Shell").tag("Terminal")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 320)
                                .padding(.bottom, 8)

                                if consoleSubTab == "Console" {
                                    VirtualMachineConsoleView(vmID: vmID)
                                } else {
                                    VirtualMachineTerminalView(vmID: vmID)
                                }
                            }

                        case .monitor:
                            VirtualMachineMonitorView(vmID: vmID)

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
                            VirtualMachineSettingsView(vmID: vmID)
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
