import SwiftUI
import AppKit

public struct RunFullAppView: View {
    @State private var runManager = FullAppRunManager.shared
    @State private var showLogs = true

    @MainActor
    private var api: XcodeBuildAPI {
        XcodeBuildAPI.shared
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
                .disabled(runManager.isRunning || api.isExecuting)
                .help("Save changes, compile project and run application in sandboxed simulator")

                Button {
                    runManager.stopApplication()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!runManager.isRunning && !api.isExecuting)
                .help("Stop application and compilation process")

                Button {
                    runManager.runLogs.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .help("Clear execution console logs")

                if runManager.currentStep == "Running application..." || PreviewManager.shared.hostedView != nil {
                    Button {
                        withAnimation(.spring()) {
                            showLogs.toggle()
                        }
                    } label: {
                        Label(showLogs ? "Show App Preview" : "Show Console Logs", systemImage: showLogs ? "iphone" : "terminal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .transition(.opacity)
                }

                Spacer()

                // Reusable copy logs button - always available when logs exist
                CopyLogsButton(logs: runManager.runLogs.joined(separator: "\n"))

                // Active Scheme indicator
                if let scheme = api.determineActiveScheme()?.name {
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
            if runManager.isRunning || api.isExecuting {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if api.isExecuting {
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

            // Real-time Console Log Stream or Actual App Preview View
            if !showLogs, let hostedView = PreviewManager.shared.hostedView {
                VStack(spacing: 12) {
                    HStack {
                        Text("Active Sandbox Application Preview")
                            .font(.system(.subheadline, design: .rounded).bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    GroupBox {
                        NativePreviewHost(hostedView: hostedView)
                            .frame(width: 320, height: 568)
                            .background(Color.black)
                            .cornerRadius(24)
                            .shadow(color: Color.black.opacity(0.35), radius: 12)
                    }
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            } else {
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
                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
            }
        }
        .onChange(of: runManager.currentStep) { _, newStep in
            if newStep == "Running application..." {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showLogs = false
                }
            } else if newStep == "Saving workspace state..." || newStep == "Compiling application project..." {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showLogs = true
                }
            }
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
