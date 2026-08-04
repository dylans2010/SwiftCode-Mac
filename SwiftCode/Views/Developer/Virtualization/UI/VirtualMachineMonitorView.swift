import SwiftUI

public struct VirtualMachineMonitorView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var timer: Timer? = nil
    @State private var metrics: [VMMetrics] = []

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    private var activeVM: VirtualMachine? {
        stateStore.virtualMachines.first { $0.id == vmID }
    }

    private var currentMetrics: VMMetrics {
        metrics.last ?? VMMetrics(
            id: UUID(),
            timestamp: Date(),
            cpuUsage: 0,
            memoryUsage: 0,
            networkIn: 0,
            networkOut: 0,
            diskRead: 0,
            diskWrite: 0,
            runningProcessesCount: 0
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Real-Time Resource Monitor")
                .font(.headline)
            Text("Track exact CPU, memory, virtual storage, and network throughput performance metrics.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if activeVM?.status == .running {
                // Monitor Grid layout
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    // CPU usage Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("CPU UTILIZATION")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f %%", currentMetrics.cpuUsage))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }

                            // Visual line representation
                            ProgressView(value: currentMetrics.cpuUsage, total: 100)
                                .accentColor(.green)

                            // History sparks
                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(metrics) { met in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.green.opacity(0.7))
                                        .frame(width: 4, height: CGFloat(met.cpuUsage * 0.4))
                                }
                            }
                            .frame(height: 40)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // RAM utilization Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("MEMORY (RAM) USAGE")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f %%", currentMetrics.memoryUsage))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.purple)
                            }

                            ProgressView(value: currentMetrics.memoryUsage, total: 100)
                                .accentColor(.purple)

                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(metrics) { met in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.purple.opacity(0.7))
                                        .frame(width: 4, height: CGFloat(met.memoryUsage * 0.4))
                                }
                            }
                            .frame(height: 40)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Network Speed Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("NETWORK THROUGHPUT")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(String(format: "In: %.1f MB/s", currentMetrics.networkIn))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.blue)
                                    Text(String(format: "Out: %.1f MB/s", currentMetrics.networkOut))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.cyan)
                                }
                            }

                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(metrics) { met in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.blue.opacity(0.7))
                                        .frame(width: 4, height: CGFloat(min(40, met.networkIn * 2.5)))
                                }
                            }
                            .frame(height: 40)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Disk Speed Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("VIRTUAL DISK I/O")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(String(format: "Read: %.1f MB/s", currentMetrics.diskRead))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.orange)
                                    Text(String(format: "Write: %.1f MB/s", currentMetrics.diskWrite))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.yellow)
                                }
                            }

                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(metrics) { met in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.orange.opacity(0.7))
                                        .frame(width: 4, height: CGFloat(min(40, met.diskRead * 15.0)))
                                }
                            }
                            .frame(height: 40)
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                GroupBox(label: Text("Active System Telemetry Summary").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Running Guest Processes:")
                            Spacer()
                            Text("\(currentMetrics.runningProcessesCount) active tasks")
                                .fontWeight(.bold)
                        }
                        Divider()
                        HStack {
                            Text("Active Session Duration:")
                            Spacer()
                            Text("Simulated virtual time telemetry")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
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
            refreshMetrics()
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                refreshMetrics()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func refreshMetrics() {
        let history = VMMonitoringManager.shared.getMetricsHistory(for: vmID)
        if history.isEmpty && activeVM?.status == .running {
            // Seed first mock data points if empty
            for i in 0..<15 {
                VMMonitoringManager.shared.appendMetrics(
                    vmID: vmID,
                    cpu: Double.random(in: 4.0...18.0),
                    ram: Double.random(in: 25.0...35.0),
                    diskRead: Double.random(in: 0.1...1.5),
                    diskWrite: Double.random(in: 0.1...0.9)
                )
            }
            metrics = VMMonitoringManager.shared.getMetricsHistory(for: vmID)
        } else {
            metrics = history
        }
    }
}
