import SwiftUI
import Observation
import os

@Observable
@MainActor
public final class PreviewManager {
    public static let shared = PreviewManager()

    // Reactive State Isolation
    public var activeSession: PreviewSession?
    public var secondarySessions: [String: PreviewSession] = [:]
    public var state = PreviewState()
    public var buildLogs: [String] = []
    public var availablePreviews: [String] = []
    public var selectedPreviewName: String?
    public var isCompiling = false
    public var hostedView: NSView?

    private let runtime = PreviewRuntime.shared
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
            self.hostedView = nil
            buildLogs.append("No SwiftUI Previews or PreviewProvider targets were found in this file.")
        }
        isCompiling = false
    }

    public func startPreviewSession(sourcePath: String, sourceCode: String, targetView: String) async {
        isCompiling = true
        buildLogs = ["Initializing persistent runtime session..."]

        do {
            let view = try await runtime.updateRuntimeSession(
                sourcePath: sourcePath,
                sourceCode: sourceCode,
                targetView: targetView
            ) { [weak self] message in
                guard let self = self else { return }
                Task { @MainActor in
                    self.buildLogs.append(message)
                }
            }

            let sessionID = runtime.activeSessionID ?? UUID().uuidString
            let session = PreviewSession(
                sessionID: sessionID,
                sourceFilePath: sourcePath,
                targetViewName: targetView,
                lastCompiledAt: runtime.lastCompiledAt ?? Date(),
                status: "Ready"
            )

            self.activeSession = session
            self.hostedView = view
            PreviewCoordinator.shared.registerSession(session)
            buildLogs.append("Persistent runtime session connected successfully.")
        } catch {
            self.activeSession = PreviewSession(
                sessionID: UUID().uuidString,
                sourceFilePath: sourcePath,
                targetViewName: targetView,
                lastCompiledAt: Date(),
                status: "Failed"
            )
            self.hostedView = nil
            buildLogs.append("Error loading preview: \(error.localizedDescription)")
            logger.error("Preview runtime session failed: \(error.localizedDescription)")
            PreviewErrorHandler.shared.handleError(error, message: "Runtime failed to load view '\(targetView)'")
        }
        isCompiling = false
    }

    public func stopActiveSession() async {
        runtime.stopRuntime()
        self.activeSession = nil
        self.hostedView = nil
        self.secondarySessions.removeAll()
        self.buildLogs = []
    }

    public func toggleDarkMode() {
        state.isDarkMode.toggle()
        updateConfiguration()
    }

    public func toggleOrientation() {
        state.isPortrait.toggle()
        updateConfiguration()
    }

    public func changeDevice(to device: String) {
        state.currentDevice = device
        updateConfiguration()
    }

    public func clearLogs() {
        buildLogs.removeAll()
    }

    private func updateConfiguration() {
        Task {
            let config = PreviewConfiguration(
                deviceName: state.currentDevice,
                isPortrait: state.isPortrait,
                isDarkMode: state.isDarkMode,
                scale: state.scale,
                dynamicTypeSize: String(describing: state.dynamicTypeSize)
            )
            await communicationService.sendConfigurationUpdate(config)
        }
    }
}
