import SwiftUI

public struct VirtualMachineDetailView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var selectedTab: DetailTab = .console

    public enum DetailTab: String, CaseIterable, Identifiable {
        case console = "Console"
        case terminal = "Terminal"
        case monitor = "Monitor"
        case snapshots = "Snapshots"
        case storage = "Storage"
        case network = "Network"
        case sharedFolders = "Shared Folders"
        case settings = "Settings"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .console: return "terminal.fill"
            case .terminal: return "command"
            case .monitor: return "chart.bar.xaxis"
            case .snapshots: return "clock.arrow.2.circlepath"
            case .storage: return "externaldrive"
            case .network: return "network"
            case .sharedFolders: return "folder.badge.plus"
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
            // Header bar
            if let vm = activeVM {
                HStack(spacing: 16) {
                    Button {
                        stateStore.selectedVMID = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(vm.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(vm.status.rawValue.uppercased())
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(statusColor(vm.status).opacity(0.15))
                                .foregroundStyle(statusColor(vm.status))
                                .cornerRadius(4)
                        }
                        Text("\(vm.osType) \(vm.version) • \(vm.cpuCores) Cores • \(String(format: "%.1f GB RAM", Double(vm.memoryMB)/1024.0)) • \(vm.storageGB) GB Disk")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: 8) {
                        if vm.status == .stopped || vm.status == .error {
                            Button {
                                triggerStart()
                            } label: {
                                Label("Start VM", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button {
                                triggerStop()
                            } label: {
                                Label("Shutdown VM", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            triggerRestart()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Restart VM")
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Tabs selection bar
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Active workspace content
                ScrollView {
                    VStack(alignment: .leading) {
                        switch selectedTab {
                        case .console:
                            VirtualMachineConsoleView(vmID: vmID)
                        case .terminal:
                            VirtualMachineTerminalView(vmID: vmID)
                        case .monitor:
                            VirtualMachineMonitorView(vmID: vmID)
                        case .snapshots:
                            VirtualMachineSnapshotsView(vmID: vmID)
                        case .storage:
                            VirtualMachineStorageView(vmID: vmID)
                        case .network:
                            VirtualMachineNetworkView(vmID: vmID)
                        case .sharedFolders:
                            VirtualMachineSharedFoldersView(vmID: vmID)
                        case .settings:
                            VirtualMachineSettingsView(vmID: vmID)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Virtual Machine Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("This VM configuration is not available or has been deleted.")
                )
                .padding()
            }
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
