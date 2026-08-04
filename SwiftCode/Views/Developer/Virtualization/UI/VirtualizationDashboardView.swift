import SwiftUI

public struct VirtualizationDashboardView: View {
    @State private var stateStore = VirtualizationStateStore.shared

    public init() {}

    private var runningVMCount: Int {
        stateStore.virtualMachines.filter { $0.status == .running }.count
    }

    private var totalCoresAllocated: Int {
        stateStore.virtualMachines.reduce(0) { $0 + $1.cpuCores }
    }

    private var totalRAMAllocatedGB: Double {
        Double(stateStore.virtualMachines.reduce(0) { $0 + $1.memoryMB }) / 1024.0
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Virtualization Dashboard")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Monitor system metrics, resource allocation, and recent guest lifecycle operations.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        stateStore.showCreateWizard = true
                    } label: {
                        Label("Create Virtual Machine", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Stat Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active Machines")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text("\(runningVMCount) / \(stateStore.virtualMachines.count)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                Spacer()
                                Image(systemName: "cpu")
                                    .font(.title)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CPU Cores Allocated")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text("\(totalCoresAllocated) Cores")
                                    .font(.title)
                                    .fontWeight(.bold)
                                Spacer()
                                Image(systemName: "cpu.fill")
                                    .font(.title)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Memory Allocated")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(String(format: "%.1f GB", totalRAMAllocatedGB))
                                    .font(.title)
                                    .fontWeight(.bold)
                                Spacer()
                                Image(systemName: "memorychip")
                                    .font(.title)
                                    .foregroundStyle(.purple)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Virtual Machines Card List
                GroupBox(label: Text("Configured Environments").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        if stateStore.virtualMachines.isEmpty {
                            ContentUnavailableView(
                                "No Environments",
                                systemImage: "cube.transparent",
                                description: Text("Create a virtual machine or import an environment to get started.")
                            )
                        } else {
                            VirtualMachineListView()
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Event / Activity Log
                GroupBox(label: Text("Recent Activity").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        if stateStore.activityLogs.isEmpty {
                            Text("No recent activity.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(stateStore.activityLogs.prefix(15)) { log in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "clock.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(log.message)
                                            .font(.subheadline)
                                        Text(log.timestamp, style: .time)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    logBadge(for: log.type)
                                }
                                .padding(.vertical, 4)
                                if log.id != stateStore.activityLogs.prefix(15).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding()
        }
    }

    @ViewBuilder
    private func logBadge(for type: ActivityLog.LogType) -> some View {
        Text(type.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(type).opacity(0.15))
            .foregroundStyle(badgeColor(type))
            .cornerRadius(4)
    }

    private func badgeColor(_ type: ActivityLog.LogType) -> Color {
        switch type {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
