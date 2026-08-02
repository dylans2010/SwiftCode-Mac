import Foundation
import Observation
import os.log

/// Main coordinate manager for running the full sandbox application workflow.
/// Driving coordination between Views, Project Resolver, XcodeBuildManager, and SimulatorManager.
@Observable
@MainActor
public final class FullAppRunManager: Sendable {
    public static let shared = FullAppRunManager()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "FullAppRun")

    // Reactive State Isolation
    public var isRunning = false
    public var currentStep = ""
    public var buildDuration: TimeInterval = 0
    public var runLogs: [String] = []

    private var timer: Timer?

    private init() {}

    /// Main workflow entry point to execute the pipeline of saving, validating, building, and running.
    public func runFullApp() async {
        guard !isRunning else {
            appendLog("[SYSTEM] Warning: Application is already running.")
            return
        }

        isRunning = true
        runLogs.removeAll()
        buildDuration = 0
        startDurationTimer()

        // 1. SAVE: Save workspace and editor states
        currentStep = "Saving workspace state..."
        appendLog("[SYSTEM] Autosaving modified workspace editor buffers...")
        await saveAllEditorBuffers()

        do {
            // 2. RESOLVE: Centralized automatic project resolution
            currentStep = "Resolving active project..."
            appendLog("[SYSTEM] Discovered active project workspace path...")
            let metadata = try ProjectResolver.shared.resolveActiveProject()

            appendLog("[SYSTEM] Resolved Metadata -> Name: \(metadata.projectName)")
            appendLog("  - Root Path: \(metadata.rootURL.path)")
            appendLog("  - Build Destination: \(metadata.buildDestination)")

            // 3. VALIDATE: Ensure toolchain pathways are healthy
            currentStep = "Validating compiler tools..."
            appendLog("[SYSTEM] Checking compiler path validity...")
            let buildPath = XcodeBuildManager.shared.getXcodeBuildPath()
            guard FileManager.default.fileExists(atPath: buildPath) else {
                throw NSError(domain: "FullAppRun", code: 1, userInfo: [NSLocalizedDescriptionKey: "xcodebuild tool path is invalid or unconfigured at: \(buildPath)"])
            }

            // 4. BUILD: Perform compile and link
            currentStep = "Compiling application project..."
            appendLog("[SYSTEM] Executing project compilation context...")

            await XcodeBuildManager.shared.runBuild(projectURL: metadata.rootURL)

            if XcodeBuildManager.shared.currentStatus == .failed {
                // Pipe compiler logs
                for log in XcodeBuildManager.shared.buildLogs {
                    appendLog(log)
                    UnifiedLogger.shared.log(log, severity: .error, subsystem: "Compiler", operation: "Compile")
                }
                throw NSError(domain: "FullAppRun", code: 2, userInfo: [NSLocalizedDescriptionKey: "Project compilation failed. Review the compiler output."])
            }

            if XcodeBuildManager.shared.currentStatus == .cancelled {
                appendLog("[SYSTEM] Build cancelled by the user.")
                stopPipeline()
                return
            }

            // Log build completion
            appendLog("[SYSTEM] Build completed successfully!")

            // 5. DEPLOY & LAUNCH: Simulator alignment
            currentStep = "Deploying and executing bundle on simulator..."
            appendLog("[SYSTEM] Aligning simulator application package...")

            await SimulatorManager.shared.refreshAll()

            guard let device = SimulatorManager.shared.selectedDevice else {
                throw NSError(domain: "FullAppRun", code: 3, userInfo: [NSLocalizedDescriptionKey: "No active or selected simulator discovered. Check Developer Settings."])
            }

            appendLog("[RUNNER] Selected target: \(device.name) (\(device.platform))")

            if device.state != .booted && device.state != .ready {
                appendLog("[RUNNER] Booting simulated hardware: \(device.name)...")
                await SimulatorManager.shared.bootSelectedDevice()
            }

            // Locate copy-aligned .app bundle
            let fm = FileManager.default
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let buildsDir = appSupport.appendingPathComponent("SwiftCode/Builds/\(metadata.rootURL.lastPathComponent)")

            let items = try fm.contentsOfDirectory(at: buildsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            guard let appBundleURL = items.first(where: { $0.pathExtension == "app" }) else {
                throw NSError(domain: "FullAppRun", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to locate compiled .app bundle inside aligned packaging folder."])
            }

            appendLog("[RUNNER] Found executable app package: \(appBundleURL.lastPathComponent)")

            await SimulatorManager.shared.installApplication(at: appBundleURL)

            let schemeName = XcodeBuildManager.shared.selectedScheme ?? metadata.rootURL.lastPathComponent
            let bundleID = "com.example.\(schemeName.lowercased().replacingOccurrences(of: " ", with: ""))"

            appendLog("[RUNNER] Launching sandbox container identifier: \(bundleID)")

            await SimulatorManager.shared.launchApplication(bundleID: bundleID)

            appendLog("[RUNNER] Application container running! Streaming runtime logs...")
            currentStep = "Running application..."

            // Feed logs immediately into system console and unified logger
            for log in SimulatorManager.shared.consoleLogs {
                appendLog("[RUNTIME] \(log)")
                UnifiedLogger.shared.log(log, severity: .runtime, subsystem: "Simulator", operation: "Runtime")
            }

        } catch {
            appendLog("[ERROR] Run pipeline failed: \(error.localizedDescription)")
            UnifiedLogger.shared.log("Pipeline execution error: \(error.localizedDescription)", severity: .error, subsystem: "FullAppRun", operation: "Pipeline")
            stopPipeline()
        }
    }

    /// Terminates the application and resets execution states
    public func stopApplication() {
        XcodeBuildManager.shared.cancelBuild()
        stopPipeline()
        appendLog("[SYSTEM] Sandbox application process halted.")
    }

    private func stopPipeline() {
        isRunning = false
        currentStep = ""
        stopDurationTimer()
    }

    private func appendLog(_ text: String) {
        runLogs.append(text)
        UnifiedLogger.shared.log(text, severity: .info, subsystem: "FullAppRun", operation: "Process")
    }

    private func saveAllEditorBuffers() async {
        // Save using core workspace logic
        ProjectSessionStore.shared.saveAll()

        // Also save active editor document in coordinator
        if let activeDoc = DocumentCoordinator.shared.activeDocument {
            do {
                try await TextBufferEngine.shared.save(content: activeDoc.content, to: activeDoc.url)
                DocumentCoordinator.shared.updateUnsavedStatus(isDirty: false)
                appendLog("[SYSTEM] Saved active changes in \(activeDoc.url.lastPathComponent) successfully.")
            } catch {
                appendLog("[ERROR] Failed to save active document buffer: \(error.localizedDescription)")
            }
        }
    }

    private func startDurationTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.buildDuration += 0.1
            }
        }
    }

    private func stopDurationTimer() {
        timer?.invalidate()
        timer = nil
    }
}
