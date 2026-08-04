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
        VStack(alignment: .leading, spacing: 16) {
            Text("Real-Time Resource Monitor")
                .font(.headline)
            Text("Track allocated hardware capabilities, active session runtimes, and networking addresses.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let vm = activeVM, vm.status == .running {
                // Monitor Grid layout
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    // CPU allocation Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("CPU ALLOCATION")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(vm.cpuCores) Cores")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }

                            ProgressView(value: Double(vm.cpuCores), total: 16)
                                .accentColor(.green)

                            Text("Allocated CPU thread capacity assigned to guest scheduler.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // RAM allocation Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("MEMORY (RAM) ALLOCATED")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f GB", Double(vm.memoryMB) / 1024.0))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.purple)
                            }

                            ProgressView(value: Double(vm.memoryMB), total: 32768)
                                .accentColor(.purple)

                            Text("Physical RAM reserved exclusively for guest kernel environment.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // IP Address Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("NETWORK IP ADDRESS")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(vm.ipAddress)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                            }

                            Text("MAC: \(vm.macAddress)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text("Host bridged NAT gateway mapping for internal sockets.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Disk Drive Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("VIRTUAL DRIVE CAPACITY")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(vm.storageGB) GB")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.orange)
                            }

                            ProgressView(value: Double(vm.storageGB), total: 1000)
                                .accentColor(.orange)

                            Text("Backed storage size allocation (/dev/vda root device).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Active Telemetry Status
                GroupBox(label: Text("Active System Telemetry Summary").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Active Session Duration:")
                            Spacer()
                            Text(uptimeString)
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                        Divider()
                        HStack {
                            Text("Virtualization Engine State:")
                            Spacer()
                            Text("Hypervisor Session Active")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Advanced Live Resource Telemetry (Graceful Offline State)
                GroupBox(label: Text("Advanced Diagnostics & Load Graphs").font(.headline)) {
                    VStack(alignment: .center, spacing: 12) {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "waveform.path.ecg.off")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.orange)
                                    .padding(.top, 8)

                                Text("Live Guest Telemetry: Offline")
                                    .font(.headline)

                                Text("Real-time guest CPU core graphs, RAM curves, internal process lists, and network packet throughput charts require the SwiftCode Guest Agent daemon to be running inside your Linux guest OS.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 550)

                                Divider()
                                    .padding(.vertical, 8)

                                Text("To install and run the guest agent, run this command in your guest shell:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("sudo apt-get install swiftcode-guest-agent && sudo systemctl enable --now swiftcode-agent")
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .background(Color.black.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            Spacer()
                        }
                    }
                    .padding(.vertical, 8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

            } else {
                ContentUnavailableView(
                    "Monitoring Inactive",
                    systemImage: "waveform.path.ecg.off",
                    description: Text("Machine is currently powered off. Launch the VM to start receiving live system telemetry.")
                )
                .frame(height: 200)
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
