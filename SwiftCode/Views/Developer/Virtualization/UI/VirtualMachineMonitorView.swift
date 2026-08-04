import SwiftUI

public struct VirtualMachineMonitorView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var timer: Timer? = nil
    @State private var uptimeString: String = "00:00:00"

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    private var activeVM: VirtualMachine? {
        stateStore.virtualMachines.first { $0.id == vmID }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Resource Performance Monitor")
                .font(.headline)
            Text("Track allocated hardware limits, active duration runtimes, and local network mapping addresses.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let vm = activeVM, vm.status == .running {
                // Monitor Grid layout
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    // CPU allocation Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("CPU THREADS", systemImage: "cpu")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(vm.cpuCores) Cores")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                            }

                            ProgressView(value: Double(vm.cpuCores), total: 16)
                                .accentColor(.green)

                            Text("Core scheduling threads allocated for computing tasks.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // RAM allocation Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("MEMORY LIMIT", systemImage: "memorychip")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f GB", Double(vm.memoryMB) / 1024.0))
                                    .font(.headline)
                                    .foregroundStyle(.purple)
                            }

                            ProgressView(value: Double(vm.memoryMB), total: 32768)
                                .accentColor(.purple)

                            Text("Reserved physical memory exclusive to the sandbox.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // IP Address Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("IP ADDRESS", systemImage: "network")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(vm.ipAddress)
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                            }

                            Text("MAC Address: \(vm.macAddress)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text("Bridged NAT adapter address mapped by host hypervisor.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Disk Drive Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("STORAGE CAPACITY", systemImage: "externaldrive")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(vm.storageGB) GB")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                            }

                            ProgressView(value: Double(vm.storageGB), total: 1000)
                                .accentColor(.orange)

                            Text("Maximum size of the backing root disk storage drive.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Active Session duration HUD
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ACTIVE SESSION TIME")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text(uptimeString)
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("HYPERVISOR STATE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text("Active Session Secure")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Guest Agent offline state panel
                GroupBox {
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "waveform.path.ecg.off")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                            .padding(.top, 4)

                        Text("Live Telemetry Diagnostics: Offline")
                            .font(.headline)

                        Text("Detailed CPU core loading graphs, RAM eviction charts, active internal guest process lists, and network bandwidth diagnostics require the SwiftCode Guest Agent daemon.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 500)

                        Divider()
                            .padding(.vertical, 4)

                        Text("To install and run the guest agent, execute inside the environment:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("sudo apt-get install swiftcode-guest-agent && sudo systemctl enable --now swiftcode-agent")
                            .font(.system(.caption2, design: .monospaced))
                            .padding(8)
                            .background(Color.black.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .padding(.vertical, 6)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

            } else {
                ContentUnavailableView(
                    "Monitoring Inactive",
                    systemImage: "waveform.path.ecg.off",
                    description: Text("The development sandbox is currently powered off. Launch the environment to stream live telemetry metrics.")
                )
                .frame(height: 220)
            }
        }
        .onAppear {
            updateUptime()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                updateUptime()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func updateUptime() {
        guard let session = VirtualizationRuntime.shared.getSession(vmID) else {
            uptimeString = "00:00:00"
            return
        }
        let seconds = Int(Date().timeIntervalSince(session.startTime))
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        uptimeString = String(format: "%02d:%02d:%02d", hrs, mins, secs)
    }
}
