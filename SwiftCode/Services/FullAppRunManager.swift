import Foundation
import Observation
import os.log

/// Main coordinate manager for running the full sandbox application workflow.
/// Driving coordination between Views, Project Resolver, XcodeBuildAPI, and SimulatorManager.
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
            // 2. RESOLVE: Resolve active project using XcodeBuildAPI
            currentStep = "Resolving active project..."
            appendLog("[SYSTEM] Discovered active project workspace path...")

            guard let activeProj = XcodeBuildAPI.shared.discoverActiveProject() else {
                throw NSError(domain: "FullAppRun", code: 10, userInfo: [NSLocalizedDescriptionKey: "No supported Xcode project or Package.swift found to build."])
            }

            appendLog("[SYSTEM] Resolved Metadata -> Name: \(activeProj.name)")
            appendLog("  - Root Path: \(activeProj.url.path)")
            appendLog("  - Build Destination: \(XcodeBuildAPI.shared.determineBuildDestination().destination)")

            // 3. VALIDATE: Ensure toolchain pathways are healthy using XcodeBuildAPI
            currentStep = "Validating compiler tools..."
            appendLog("[SYSTEM] Checking compiler path validity...")
            let validation = await XcodeBuildAPI.shared.validateBuildEnvironment()
            if !validation.isValid {
                throw NSError(domain: "FullAppRun", code: 1, userInfo: [NSLocalizedDescriptionKey: validation.errorDescription ?? "Build environment is invalid."])
            }

            // 4. BUILD: Perform compile and link using XcodeBuildAPI
            currentStep = "Compiling application project..."
            appendLog("[SYSTEM] Executing project compilation context...")

            let buildResult = await XcodeBuildAPI.shared.buildProject()

            if buildResult.status == .failed {
                // Pipe compiler logs
                for log in buildResult.logs.lines {
                    appendLog(log)
                    UnifiedLogger.shared.log(log, severity: .error, subsystem: "Compiler", operation: "Compile")
                }
                throw NSError(domain: "FullAppRun", code: 2, userInfo: [NSLocalizedDescriptionKey: "Project compilation failed. Review the compiler output."])
            }

            if buildResult.status == .cancelled {
                appendLog("[SYSTEM] Build cancelled by the user.")
                stopPipeline()
                return
            }

            // Log build completion
            appendLog("[SYSTEM] Build completed successfully!")

            // Populate the PreviewManager hostedView with the successfully built SwiftUI code
            if let activeDoc = DocumentCoordinator.shared.activeDocument {
                let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(activeDoc.content, filename: activeDoc.url.path)
                await PreviewManager.shared.startFreshLivePreviewSession(
                    sourcePath: activeDoc.url.path,
                    sourceCode: preparedCode,
                    targetViewName: PreviewManager.shared.selectedPreviewName
                )
            }

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

            // Locate copy-aligned .app bundle via XcodeBuildAPI
            guard let appBundleURL = XcodeBuildAPI.shared.determineAppBundleURL() else {
                throw NSError(domain: "FullAppRun", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to locate compiled .app bundle inside aligned packaging folder."])
            }

            appendLog("[RUNNER] Found executable app package: \(appBundleURL.lastPathComponent)")

            await SimulatorManager.shared.installApplication(at: appBundleURL)

            let bundleID = XcodeBuildAPI.shared.determineBundleIdentifier()

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
        XcodeBuildAPI.shared.cancelBuild()
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
