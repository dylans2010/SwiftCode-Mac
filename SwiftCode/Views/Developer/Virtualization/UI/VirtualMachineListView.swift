import SwiftUI

public struct VirtualMachineListView: View {
    @State private var stateStore = VirtualizationStateStore.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            ForEach(stateStore.virtualMachines) { vm in
                Button {
                    stateStore.selectedVMID = vm.id
                } label: {
                    HStack(spacing: 16) {
                        // Brand Icon for OS type
                        Image(systemName: osIcon(vm.osType))
                            .font(.system(size: 24))
                            .foregroundStyle(osColor(vm.osType))
                            .frame(width: 52, height: 52)
                            .background(osColor(vm.osType).opacity(0.1))
                            .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(vm.name)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)

                                statusBadge(for: vm.status)
                            }

                            // Subtitle resource details
                            HStack(spacing: 10) {
                                Text("\(vm.osType) \(vm.version)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text("•")
                                    .foregroundStyle(.secondary)

                                Label("\(vm.cpuCores) cores", systemImage: "cpu")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Label(String(format: "%.1f GB RAM", Double(vm.memoryMB) / 1024.0), systemImage: "memorychip")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Label("\(vm.storageGB) GB Disk", systemImage: "externaldrive")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        // Action Buttons
                        HStack(spacing: 12) {
                            if vm.status == .stopped || vm.status == .error {
                                Button {
                                    triggerStart(vm.id)
                                } label: {
                                    Label("Start", systemImage: "play.fill")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.bordered)
                                .help("Power on this development environment")
                            } else {
                                Button {
                                    triggerStop(vm.id)
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.bordered)
                                .help("Shutdown this running environment")
                            }

                            Button {
                                stateStore.selectedVMID = vm.id
                            } label: {
                                Text("Open Details")
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        stateStore.selectedVMID = vm.id
                    } label: {
                        Label("Open Configuration", systemImage: "slider.horizontal.3")
                    }

                    Divider()

                    if vm.status == .stopped {
                        Button {
                            triggerStart(vm.id)
                        } label: {
                            Label("Power On", systemImage: "play.fill")
                        }
                    } else {
                        Button {
                            triggerStop(vm.id)
                        } label: {
                            Label("Force Shutdown", systemImage: "stop.fill")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        stateStore.deleteVM(id: vm.id)
                    } label: {
                        Label("Delete Environment", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for status: VMStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
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

    private func osIcon(_ type: String) -> String {
        switch type {
        case "Ubuntu": return "cpu"
        case "Debian": return "circle.circle"
        case "Fedora": return "shippingbox"
        case "Alpine": return "snowflake"
        default: return "terminal"
        }
    }

    private func osColor(_ type: String) -> Color {
        switch type {
        case "Ubuntu": return .orange
        case "Debian": return .red
        case "Fedora": return .blue
        case "Alpine": return .teal
        default: return .secondary
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
