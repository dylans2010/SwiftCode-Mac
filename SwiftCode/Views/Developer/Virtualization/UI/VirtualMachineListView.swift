import SwiftUI

public struct VirtualMachineListView: View {
    @State private var stateStore = VirtualizationStateStore.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            ForEach(stateStore.virtualMachines) { vm in
                HStack(spacing: 16) {
                    // OS Logo representation
                    Image(systemName: "cpu")
                        .font(.title)
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(vm.name)
                                .font(.headline)
                            Spacer()
                            statusBadge(for: vm.status)
                        }

                        Text("\(vm.osType) \(vm.version) • \(vm.cpuCores) Cores • \(String(format: "%.1f GB RAM", Double(vm.memoryMB)/1024.0)) • \(vm.storageGB) GB Disk")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Quick Action triggers
                    HStack(spacing: 8) {
                        if vm.status == .stopped || vm.status == .error {
                            Button {
                                triggerStart(vm.id)
                            } label: {
                                Image(systemName: "play.fill")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            .help("Start Virtual Machine")
                        } else {
                            Button {
                                triggerStop(vm.id)
                            } label: {
                                Image(systemName: "stop.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Stop Virtual Machine")
                        }

                        Button {
                            stateStore.selectedVMID = vm.id
                        } label: {
                            Text("Configure")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .controlSize(.small)

                        Button(role: .destructive) {
                            stateStore.deleteVM(id: vm.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete VM")
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for status: VMStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.15))
            .foregroundStyle(statusColor(status))
            .cornerRadius(4)
    }

    private func statusColor(_ status: VMStatus) -> Color {
        switch status {
        case .running: return .green
        case .starting, .resumed: return .blue
        case .stopped: return .secondary
        case .pausing, .paused: return .orange
        case .stopping: return .orange
        case .error: return .red
        }
    }

    private func triggerStart(_ id: UUID) {
        Task {
            let ctrl = SCVirtualizationEngine.shared.createController(for: id)
            await ctrl.start()
        }
    }

    private func triggerStop(_ id: UUID) {
        Task {
            let ctrl = SCVirtualizationEngine.shared.createController(for: id)
            await ctrl.stop()
        }
    }
}
