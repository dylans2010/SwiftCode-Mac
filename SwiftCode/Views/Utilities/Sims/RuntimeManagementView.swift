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
