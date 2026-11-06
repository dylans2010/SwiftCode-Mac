import SwiftUI
import AppKit

public struct SimulatorDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = SimulatorManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Card 1: Environment Probe Info
                    environmentInfoCard

                    // Card 2: Execution History Log (Bounded Ring Buffer)
                    executionHistoryCard
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Simulator Subsystem Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: copyAllDiagnosticsToClipboard) {
                        Label("Copy All Diagnostics", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private var environmentInfoCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Environment Probes & Metadata", systemImage: "stethoscope")
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
                    .disabled(manager.isRefreshing)
                }

                Divider()

                let diag = manager.diagnostics

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    diagnosticRow(title: "Developer Directory", value: diag.developerDirectory ?? "Pending probe...")
                    diagnosticRow(title: "Xcode Version", value: diag.xcodeVersion ?? "Pending probe...")
                    diagnosticRow(title: "xcrun Path", value: diag.xcrunLocation ?? "Not Found")
                    diagnosticRow(title: "simctl CLI Operational", value: diag.simctlAvailable ? "Yes" : "No", isStatus: true, statusValue: diag.simctlAvailable)
                    diagnosticRow(title: "SDK Runtimes Discovered", value: "\(diag.runtimeCount)")
                    diagnosticRow(title: "Configured Simulators", value: "\(diag.deviceCount)")
                    diagnosticRow(title: "Running Simulators", value: "\(diag.runningSimulatorCount)")
                    diagnosticRow(title: "Pipeline Last Refresh", value: diag.lastRefreshDate?.formatted(date: .abbreviated, time: .standard) ?? "Never")
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private var executionHistoryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Recent simctl/Command Execution Log", systemImage: "terminal.fill")
                        .font(.headline)
                        .foregroundColor(.cyan)
                    Spacer()
                }

                Divider()

                let commands = manager.diagnostics.recentCommands

                if commands.isEmpty {
                    Text("No commands executed in this session yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(commands) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(record.command.executableURL.lastPathComponent)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)

                                    Text(record.command.arguments.joined(separator: " "))
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    outcomeLabel(record.outcome)

                                    Button {
                                        copyCommandToClipboard(record)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy command log details")
                                }

                                HStack {
                                    Text("Duration: \(String(format: "%.3f", Double(record.duration.components.seconds) + Double(record.duration.components.attoseconds) * 1e-18))s")
                                        .font(.caption2)
                                    Spacer()
                                    Text("Started at: \(record.startedAt.formatted(date: .omitted, time: .standard))")
                                        .font(.caption2)
                                }
                                .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func diagnosticRow(title: String, value: String, isStatus: Bool = false, statusValue: Bool = false) -> some View {
        HStack {
            Text(title)
                .bold()
                .foregroundColor(.secondary)
            Spacer()
            if isStatus {
                HStack(spacing: 4) {
                    Image(systemName: statusValue ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(statusValue ? .green : .red)
                    Text(value)
                        .foregroundColor(statusValue ? .green : .red)
                }
            } else {
                Text(value)
                    .foregroundColor(.primary)
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func outcomeLabel(_ outcome: CommandOutcome) -> some View {
        switch outcome {
        case .success:
            Text("Success")
                .font(.caption)
                .bold()
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.1))
                .cornerRadius(4)
        case .nonZeroExit(let code):
            Text("Exit \(code)")
                .font(.caption)
                .bold()
                .foregroundColor(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
        case .timedOut:
            Text("Timeout")
                .font(.caption)
                .bold()
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
        case .cancelled:
            Text("Cancelled")
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        case .launchFailed:
            Text("Launch Error")
                .font(.caption)
                .bold()
                .foregroundColor(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
        }
    }

    private func copyCommandToClipboard(_ record: CommandExecutionRecord) {
        let text = """
        COMMAND: \(record.command.executableURL.path) \(record.command.arguments.joined(separator: " "))
        OUTCOME: \(record.outcome)
        EXIT CODE: \(record.exitCode)
        DURATION: \(record.duration)
        STDOUT:
        \(record.stdoutString)
        STDERR:
        \(record.stderrString)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyAllDiagnosticsToClipboard() {
        let diag = manager.diagnostics
        let text = """
        === SWIFTCODE SIMULATOR SUBSYSTEM DIAGNOSTICS ===
        Developer Directory: \(diag.developerDirectory ?? "N/A")
        Xcode Version: \(diag.xcodeVersion ?? "N/A")
        xcrun Location: \(diag.xcrunLocation ?? "N/A")
        simctl Operational: \(diag.simctlAvailable)
        Runtimes Discovered: \(diag.runtimeCount)
        Devices Discovered: \(diag.deviceCount)
        Active Booted: \(diag.runningSimulatorCount)
        Last Refresh Date: \(diag.lastRefreshDate?.formatted() ?? "N/A")
        Discovery Duration: \(diag.lastDiscoveryDuration ?? .zero)
        =================================================
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
