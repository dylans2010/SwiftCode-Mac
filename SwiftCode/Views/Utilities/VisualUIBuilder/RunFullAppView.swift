import SwiftUI
import AppKit

public struct RunFullAppView: View {
    @State private var runManager = FullAppRunManager.shared

    @MainActor
    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Execution Controls Header
            HStack(spacing: 12) {
                Button {
                    Task {
                        await runManager.runFullApp()
                    }
                } label: {
                    Label("Run App", systemImage: "play.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(runManager.isRunning || buildManager.isBuilding)
                .help("Save changes, compile project and run application in sandboxed simulator")

                Button {
                    runManager.stopApplication()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!runManager.isRunning && !buildManager.isBuilding)
                .help("Stop application and compilation process")

                Button {
                    runManager.runLogs.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .help("Clear execution console logs")

                Spacer()

                // Reusable copy logs button - always available when logs exist
                CopyLogsButton(logs: runManager.runLogs.joined(separator: "\n"))

                // Active Scheme indicator
                if let scheme = buildManager.selectedScheme {
                    Text(scheme)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Compilation & Launch HUD Status Panel
            if runManager.isRunning || buildManager.isBuilding {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if buildManager.isBuilding {
                            ProgressView()
                                .controlSize(.small)
                            Text("Building project...")
                                .font(.subheadline.bold())
                        } else {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .foregroundColor(.green)
                            Text("Running on Simulator...")
                                .font(.subheadline.bold())
                                .foregroundColor(.green)
                        }
                        Spacer()
                        Text(String(format: "%.1f s", runManager.buildDuration))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if !runManager.currentStep.isEmpty {
                        Text(runManager.currentStep)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.05))
                Divider()
            }

            // Real-time Console Log Stream View
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if runManager.runLogs.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("Console Stream Idle")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Press 'Run App' to automatically save, build, and launch your project.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 40)
                        } else {
                            ForEach(runManager.runLogs.indices, id: \.self) { idx in
                                let log = runManager.runLogs[idx]
                                Text(log)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(logColor(for: log))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                    }
                    .padding(12)
                }
                .onChange(of: runManager.runLogs.count) { _, newCount in
                    if newCount > 0 {
                        withAnimation {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.95))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Helper to color console logs based on patterns
    private func logColor(for line: String) -> Color {
        if line.contains("[ERROR]") || line.contains("error:") || line.hasPrefix("❌") {
            return .red
        }
        if line.contains("[WARNING]") || line.contains("warning:") || line.hasPrefix("⚠️") {
            return .yellow
        }
        if line.contains("[SYSTEM]") || line.contains("[MANAGER]") {
            return .cyan
        }
        if line.contains("[RUNNER]") {
            return .green
        }
        return .white
    }
}
