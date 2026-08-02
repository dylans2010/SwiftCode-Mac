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

    // Sequence tracking for newest-request-wins concurrency safety
    private var currentSessionRequestID: UUID?

    private let runtime = PreviewRuntime.shared
    private let discoveryService = PreviewDiscoveryService()
    private let communicationService = PreviewCommunicationService()
    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "PreviewManager")

    private init() {}

    public func loadPreviews(forFileAt path: String, content: String) async {
        isCompiling = true
        buildLogs = ["Discovering previews..."]

        let requestID = UUID()
        self.currentSessionRequestID = requestID

        // 1. Transition to INIT
        var session = PreviewSession(
            sessionID: UUID().uuidString,
            sourceFilePath: path,
            targetViewName: "",
            status: "Initializing",
            state: .init_state
        )
        self.activeSession = session
        PreviewDiagnostics.shared.addLog(category: "state", message: "Transition to INIT")

        guard self.currentSessionRequestID == requestID else { return }

        // 2. Transition to SOURCE_RECEIVED
        session.state = .sourceReceived
        session.status = "Source received"
        self.activeSession = session
        PreviewDiagnostics.shared.addLog(category: "state", message: "Transition to SOURCE_RECEIVED for \(path)")

        guard self.currentSessionRequestID == requestID else { return }

        // 3. Transition to DISCOVERING
        session.state = .discovering
        session.status = "Discovering"
        self.activeSession = session
        PreviewDiagnostics.shared.addLog(category: "state", message: "Transition to DISCOVERING")

        let discovered = await discoveryService.discoverPreviewTargets(inSourceCode: content, filename: path)

        guard self.currentSessionRequestID == requestID else { return }

        var allTargets = discovered

        self.availablePreviews = allTargets

        if let first = allTargets.first {
            selectedPreviewName = first
            await startPreviewSession(sourcePath: path, sourceCode: content, targetView: first, requestID: requestID)
        } else {
            // 4. Transition to NO_CANDIDATES
            session.state = .noCandidates
            session.status = "No candidates found"
            self.activeSession = session
            PreviewDiagnostics.shared.addLog(category: "state", message: "Transition to NO_CANDIDATES")

            selectedPreviewName = nil
            self.hostedView = nil
            buildLogs.append("No SwiftUI Previews or PreviewProvider targets were found in this file.")
        }
        isCompiling = false
    }

    @MainActor
    public func synchronizeArtboardsForPreviews(sourcePath: String, sourceCode: String) {
        guard let document = DocumentCoordinator.shared.visualUIDocument else { return }
        let parsed = PreviewBlockParser.parsePreviews(in: sourceCode)

        var newArtboards = document.scene.artboards.filter { $0.name == "Default" }
        if newArtboards.isEmpty {
            let rootNode = VisualComponentNode(type: .vStack)
            let defaultArtboard = VisualUIArtboard(name: "Default", deviceFrame: VisualUISettings.shared.selectedDevice, rootNode: rootNode)
            newArtboards.append(defaultArtboard)
        }

        for preview in parsed {
            let name = preview.title
            if name == "Default" { continue }
            if let existing = document.scene.artboards.first(where: { $0.name == name }) {
                newArtboards.append(existing)
            } else {
                let rootNode = VisualComponentNode(type: .vStack)
                let artboard = VisualUIArtboard(name: name, deviceFrame: VisualUISettings.shared.selectedDevice, rootNode: rootNode)
                newArtboards.append(artboard)
            }
        }

        document.scene.artboards = newArtboards
        if document.scene.activeArtboardID == nil || !document.scene.artboards.contains(where: { $0.id == document.scene.activeArtboardID }) {
            document.scene.activeArtboardID = document.scene.artboards.first?.id
        }
    }

    public func startPreviewSession(sourcePath: String, sourceCode: String, targetView: String, requestID: UUID? = nil) async {
        let actualRequestID = requestID ?? UUID()
        if requestID == nil {
            self.currentSessionRequestID = actualRequestID
        }

        isCompiling = true
        buildLogs = ["Initializing persistent runtime session..."]

        // ALWAYS create a brand new PreviewSession and never reuse/continue an existing session
        var session = PreviewSession(
            sessionID: UUID().uuidString,
            sourceFilePath: sourcePath,
            targetViewName: targetView,
            status: "Compiling",
            state: .compiling
        )

        // 4. Transition to COMPILING
        session.state = .compiling
        session.status = "Compiling"
        self.activeSession = session
        PreviewDiagnostics.shared.addLog(category: "state", message: "Transition to COMPILING for target '\(targetView)'")

        guard self.currentSessionRequestID == actualRequestID else { return }

        // Synchronize parsed previews with artboards automatically
        synchronizeArtboardsForPreviews(sourcePath: sourcePath, sourceCode: sourceCode)

        do {
            // 5. Transition to RENDERING
            session.state = .rendering
            session.status = "Rendering"
            self.activeSession = session
            PreviewDiagnostics.shared.addLog(category: "state", message: "Transition to RENDERING for target '\(targetView)'")

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

            guard self.currentSessionRequestID == actualRequestID else { return }

            // 6. Transition to RENDERED
            let finalSessionID = runtime.activeSessionID ?? session.sessionID
            let finalSession = PreviewSession(
                sessionID: finalSessionID,
                sourceFilePath: sourcePath,
                targetViewName: targetView,
                lastCompiledAt: runtime.lastCompiledAt ?? Date(),
                status: "Ready",
                state: .rendered
            )

            self.activeSession = finalSession
            self.hostedView = view
            PreviewCoordinator.shared.registerSession(finalSession)
            PreviewDiagnostics.shared.addLog(category: "state", message: "Transition to RENDERED successfully")
            buildLogs.append("Persistent runtime session connected successfully.")
        } catch {
            guard self.currentSessionRequestID == actualRequestID else { return }

            // 6. Transition to FAILED_KEEP_LAST or FAILED_NO_PRIOR
            let hasPrior = self.hostedView != nil
            let finalState: PreviewSessionState = hasPrior ? .failedKeepLast : .failedNoPrior

            let finalSession = PreviewSession(
                sessionID: session.sessionID,
                sourceFilePath: sourcePath,
                targetViewName: targetView,
                lastCompiledAt: Date(),
                status: "Failed",
                state: finalState
            )

            self.activeSession = finalSession
            if !hasPrior {
                self.hostedView = nil
            }
            PreviewDiagnostics.shared.addLog(category: "error", message: "Runtime failed to load view '\(targetView)': \(error.localizedDescription)")
            PreviewDiagnostics.shared.addLog(category: "state", message: "Transition to \(finalState.rawValue)")
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
