import SwiftUI

struct RuntimeManagementView: View {
    @State private var manager = SimulatorManager.shared

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Simulator Discovery Diagnostics", systemImage: "stethoscope")
                        .font(.headline)
                        .foregroundColor(.teal)
                    Spacer()

                    Button {
                        Task {
                            await manager.refreshAll()
                        }
                    } label: {
                        Label("Run Diagnostics", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                if let diag = manager.pipelineDiagnostics {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Xcode Path")
                                .bold()
                            Spacer()
                            Text(diag.xcodePath)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Xcode Version")
                                .bold()
                            Spacer()
                            Text(diag.xcodeVersion)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("xcrun Location")
                                .bold()
                            Spacer()
                            Text(diag.xcrunVersion.contains("xcrun version") ? "/usr/bin/xcrun" : "Not Found")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("simctl Availability")
                                .bold()
                            Spacer()
                            Image(systemName: diag.isSimctlAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(diag.isSimctlAvailable ? .green : .red)
                        }

                        HStack {
                            Text("Runtimes Count")
                                .bold()
                            Spacer()
                            Text("\(diag.runtimeCount)")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Devices Count")
                                .bold()
                            Spacer()
                            Text("\(diag.deviceCount)")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Running Simulators")
                                .bold()
                            Spacer()
                            Text("\(diag.runningCount)")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Last Refresh Time")
                                .bold()
                            Spacer()
                            Text(diag.lastRefreshTime.formatted(date: .abbreviated, time: .standard))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Discovery Duration")
                                .bold()
                            Spacer()
                            Text(String(format: "%.2f s", diag.discoveryDuration))
                                .foregroundColor(.secondary)
                        }

                        if !diag.latestStderr.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Latest STDERR Output")
                                    .bold()
                                Text(diag.latestStderr)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.red)
                                    .padding(8)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .padding(.top, 4)
                        }

                        HStack {
                            Text("Latest Exit Code")
                                .bold()
                            Spacer()
                            Text("\(diag.latestExitCode)")
                                .foregroundColor(diag.latestExitCode == 0 ? .green : .red)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Running first discovery diagnostic check...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }
}

public struct PipelineDiagnostics: Sendable {
    public let xcodePath: String
    public let xcodeVersion: String
    public let xcrunVersion: String
    public let isSimctlAvailable: Bool
    public let runtimeCount: Int
    public let deviceCount: Int
    public let runningCount: Int
    public let lastRefreshTime: Date
    public let discoveryDuration: Double
    public let latestStderr: String
    public let latestExitCode: Int32
}

extension SimulatorManager {
    public var pipelineDiagnostics: PipelineDiagnostics? {
        guard let lastRefreshDate = diagnostics.lastRefreshDate else {
            return nil
        }

        let lastCmd = diagnostics.recentCommands.last
        let durationInSeconds: Double
        if let duration = diagnostics.lastDiscoveryDuration {
            durationInSeconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1.0e18
        } else {
            durationInSeconds = 0.0
        }

        return PipelineDiagnostics(
            xcodePath: diagnostics.developerDirectory ?? "Unknown",
            xcodeVersion: diagnostics.xcodeVersion ?? "Unknown",
            xcrunVersion: diagnostics.xcrunLocation != nil ? "xcrun version 1" : "Not Found",
            isSimctlAvailable: diagnostics.simctlAvailable,
            runtimeCount: diagnostics.runtimeCount,
            deviceCount: diagnostics.deviceCount,
            runningCount: diagnostics.runningSimulatorCount,
            lastRefreshTime: lastRefreshDate,
            discoveryDuration: durationInSeconds,
            latestStderr: lastCmd?.stderrString ?? "",
            latestExitCode: lastCmd?.exitCode ?? 0
        )
    }
}
