import SwiftUI
import AppKit

public struct RunFullAppView: View {
    @State private var runLogs: [String] = []
    @State private var isRunning = false
    @State private var currentStep = ""
    @State private var buildDuration: TimeInterval = 0
    @State private var timer: Timer?

    @MainActor
    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
    }

    @MainActor
    private var simulatorManager: SimulatorManager {
        SimulatorManager.shared
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Execution Controls Header
            HStack(spacing: 12) {
                Button {
                    Task {
                        await runFullAppWorkflow()
                    }
                } label: {
                    Label("Run App", systemImage: "play.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRunning || buildManager.isBuilding)
                .help("Save changes, compile project and run application in sandboxed simulator")

                Button {
                    stopApplication()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isRunning && !buildManager.isBuilding)
                .help("Stop application and compilation process")

                Button {
                    runLogs.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .help("Clear execution console logs")

                Spacer()

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
            if isRunning || buildManager.isBuilding {
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
                        Text(String(format: "%.1f s", buildDuration))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if !currentStep.isEmpty {
                        Text(currentStep)
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
                        if runLogs.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("Console Stream Idle")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Press 'Run App' to start compiling and executing your project.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 40)
                        } else {
                            ForEach(runLogs.indices, id: \.self) { idx in
                                let log = runLogs[idx]
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
                .onChange(of: runLogs.count) { _, newCount in
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

    private func saveEditorBuffers() async {
        if let activeDoc = DocumentCoordinator.shared.activeDocument {
            do {
                try await TextBufferEngine.shared.save(content: activeDoc.content, to: activeDoc.url)
                DocumentCoordinator.shared.updateUnsavedStatus(isDirty: false)
                appendLog("[SYSTEM] Saved active changes in \(activeDoc.url.lastPathComponent) successfully.")
            } catch {
                appendLog("[ERROR] Failed to save active document before compile: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func runFullAppWorkflow() async {
        guard let projectURL = DocumentCoordinator.shared.projectURL else {
            appendLog("[ERROR] No active project is linked to Workspace.")
            return
        }

        isRunning = true
        currentStep = "Saving changes..."
        buildDuration = 0
        runLogs.removeAll()

        startDurationTimer()

        // 1. Save all editor buffers first
        await saveEditorBuffers()

        // 2. Start Project Compilation
        appendLog("[SYSTEM] Initiating full project compilation context...")
        currentStep = "Compiling project..."

        await buildManager.runBuild(projectURL: projectURL)

        if buildManager.currentStatus == .failed {
            appendLog("[ERROR] Project compilation failed. See diagnostics above.")
            stopDurationTimer()
            isRunning = false
            currentStep = "Compilation failed."
            return
        }

        if buildManager.currentStatus == .cancelled {
            appendLog("[SYSTEM] Compilation was cancelled by user.")
            stopDurationTimer()
            isRunning = false
            currentStep = "Execution cancelled."
            return
        }

        // Import build logs
        for log in buildManager.buildLogs {
            appendLog(log)
        }

        // 3. Launching simulator and installing application package
        appendLog("[SYSTEM] Launching application on simulator...")
        currentStep = "Launching simulator device..."

        await simulatorManager.refreshAll()

        guard let device = simulatorManager.selectedDevice else {
            appendLog("[ERROR] No active/selected simulator device discovered. Ensure a simulator is selected in developer settings.")
            isRunning = false
            stopDurationTimer()
            return
        }

        appendLog("[MANAGER] Selected Device: \(device.name) (\(device.platform))")

        // Boot device if not booted
        if device.state != .booted && device.state != .ready {
            await simulatorManager.bootSelectedDevice()
        }

        // Determine app bundle path
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let buildsDir = appSupport.appendingPathComponent("SwiftCode/Builds/\(projectURL.lastPathComponent)")

        do {
            let items = try fm.contentsOfDirectory(at: buildsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            guard let appBundleURL = items.first(where: { $0.pathExtension == "app" }) else {
                appendLog("[ERROR] Failed to locate compiled .app package inside builds workspace.")
                isRunning = false
                stopDurationTimer()
                return
            }

            appendLog("[RUNNER] Found executable app package: \(appBundleURL.lastPathComponent)")
            currentStep = "Deploying bundle to simulator..."

            await simulatorManager.installApplication(at: appBundleURL)

            // Resolve bundle identifier dynamically (default to demo or scheme slug)
            let schemeName = buildManager.selectedScheme ?? projectURL.lastPathComponent
            let bundleID = "com.example.\(schemeName.lowercased().replacingOccurrences(of: " ", with: ""))"

            appendLog("[RUNNER] Starting application sandbox container: \(bundleID)")
            currentStep = "Executing application container..."

            await simulatorManager.launchApplication(bundleID: bundleID)

            appendLog("[RUNNER] Sandbox container launched successfully! Streaming logs from application lifecycle...")
            currentStep = "Running application..."

            // Feed simulator logs as they come in
            for log in simulatorManager.consoleLogs {
                appendLog("[RUNTIME] \(log)")
            }

        } catch {
            appendLog("[ERROR] Sandbox execution error: \(error.localizedDescription)")
            isRunning = false
            stopDurationTimer()
        }
    }

    private func stopApplication() {
        buildManager.cancelBuild()
        isRunning = false
        stopDurationTimer()
        appendLog("[SYSTEM] Execution process stopped.")
        currentStep = "Execution halted."
    }

    private func appendLog(_ text: String) {
        runLogs.append(text)
    }

    private func startDurationTimer() {
        buildDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            buildDuration += 0.1
        }
    }

    private func stopDurationTimer() {
        timer?.invalidate()
        timer = nil
    }
}
