import SwiftUI
import Observation
import os

@Observable
@MainActor
public final class PreviewManager {
    public static let shared = PreviewManager()

    // Public state
    public private(set) var activeSession: PreviewSession?
    public private(set) var buildLogs: [String] = []
    public var selectedPreviewName: String?
    public var availablePreviews: [String] = []

    public var isCompiling = false
    public var configuration = PreviewConfiguration()
    public var scale: Double = 1.0 {
        didSet {
            configuration.scale = scale
            updateConfiguration()
        }
    }

    // Support for multiple simultaneous preview windows
    public private(set) var secondarySessions: [String: PreviewSession] = [:]

    private let engine = PreviewEngine()
    private let discoveryService = PreviewDiscoveryService()
    private let communicationService = PreviewCommunicationService()
    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "PreviewManager")

    private init() {}

    public func loadPreviews(forFileAt path: String, content: String) async {
        isCompiling = true
        buildLogs = ["Discovering previews..."]

        let discovered = await discoveryService.discoverPreviews(inSourceCode: content)
        self.availablePreviews = discovered

        if let first = discovered.first {
            selectedPreviewName = first
            await startPreviewSession(sourcePath: path, sourceCode: content, targetView: first)
        } else {
            selectedPreviewName = nil
            self.activeSession = nil
            buildLogs.append("No SwiftUI Previews or PreviewProvider targets were found in this file.")
        }
        isCompiling = false
    }

    public func startPreviewSession(sourcePath: String, sourceCode: String, targetView: String) async {
        isCompiling = true
        buildLogs = ["Initializing preview environment..."]

        do {
            // Run on engine actor (off-main-thread rendering work)
            let session = try await engine.runPreviewSession(
                sourceFilePath: sourcePath,
                sourceCode: sourceCode,
                targetView: targetView
            ) { [weak self] message in
                guard let self = self else { return }
                Task { @MainActor in
                    self.buildLogs.append(message)
                }
            }
            self.activeSession = session
            buildLogs.append("Preview load succeeded.")
        } catch {
            // Graceful recovery when rendering fails
            self.activeSession = PreviewSession(
                sessionID: UUID().uuidString,
                sourceFilePath: sourcePath,
                targetViewName: targetView,
                lastCompiledAt: Date(),
                status: "Failed"
            )
            buildLogs.append("Graceful Recovery: Preview load failed, but workspace remains operational. details: \(error.localizedDescription)")
            logger.error("Preview Session failed: \(error.localizedDescription). Recovered gracefully.")
        }
        isCompiling = false
    }

    /// Exposes rendering pipeline mapping based on visual builders
    public func pipelineForFramework(_ framework: VisualUIFramework) async -> String {
        await engine.determineRenderingPipeline(for: framework)
    }

    /// Supports starting a secondary simultaneous preview window
    public func startSecondaryPreviewSession(windowID: String, sourcePath: String, sourceCode: String, targetView: String) async {
        do {
            let session = try await engine.runPreviewSession(
                sourceFilePath: sourcePath,
                sourceCode: sourceCode,
                targetView: targetView
            ) { _ in }
            secondarySessions[windowID] = session
        } catch {
            logger.error("Failed to start secondary preview window: \(error.localizedDescription)")
        }
    }

    public func stopActiveSession() async {
        await engine.stopPreviewSession()
        self.activeSession = nil
        self.secondarySessions.removeAll()
        self.buildLogs = []
    }

    public func toggleDarkMode() {
        configuration.isDarkMode.toggle()
        updateConfiguration()
    }

    public func toggleOrientation() {
        configuration.isPortrait.toggle()
        updateConfiguration()
    }

    public func changeDevice(to device: String) {
        configuration.deviceName = device
        updateConfiguration()
    }

    public func clearLogs() {
        buildLogs.removeAll()
    }

    private func updateConfiguration() {
        Task {
            await communicationService.sendConfigurationUpdate(configuration)
        }
    }
}
