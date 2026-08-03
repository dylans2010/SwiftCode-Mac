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

    /// Validates the build pipeline constraints strictly. Throws a detailed error on any validation failure.
    public func validatePreviewBuildPipeline() async throws {
        // 1. Workspace / Project Resolver validation
        let metadata: ResolvedProjectMetadata
        do {
            metadata = try ProjectResolver.shared.resolveActiveProject()
        } catch {
            throw NSError(domain: "PreviewBuild", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active workspace or project resolved."])
        }

        // 2. Project
        guard let _ = XcodeBuildAPI.shared.determineActiveProject() else {
            throw NSError(domain: "PreviewBuild", code: 402, userInfo: [NSLocalizedDescriptionKey: "Active target project not found."])
        }

        // 3. Scheme
        guard let _ = XcodeBuildAPI.shared.determineActiveScheme() else {
            throw NSError(domain: "PreviewBuild", code: 403, userInfo: [NSLocalizedDescriptionKey: "No active scheme selected for the target project."])
        }

        // 4. Bundle Identifier
        let bundleID = XcodeBuildAPI.shared.determineBundleIdentifier()
        if bundleID.isEmpty {
            throw NSError(domain: "PreviewBuild", code: 404, userInfo: [NSLocalizedDescriptionKey: "Bundle identifier is invalid or empty."])
        }

        // 5. Swift Version Check (checks swiftc executable)
        let fm = FileManager.default
        let hasSwiftc = fm.fileExists(atPath: "/usr/bin/swiftc") || fm.fileExists(atPath: "/usr/bin/swift")
        if !hasSwiftc {
            throw NSError(domain: "PreviewBuild", code: 405, userInfo: [NSLocalizedDescriptionKey: "Swift compiler tools (swiftc) are missing in the current system."])
        }

        // 6. SDK Environment validation
        let validation = await XcodeBuildAPI.shared.validateBuildEnvironment()
        if !validation.isValid {
            throw NSError(domain: "PreviewBuild", code: 406, userInfo: [NSLocalizedDescriptionKey: validation.errorDescription ?? "Build environment SDK validation failed."])
        }

        // 7. Dependencies check
        if metadata.isSwiftPackage {
            guard let packageURL = metadata.packageSwiftURL, fm.fileExists(atPath: packageURL.path) else {
                throw NSError(domain: "PreviewBuild", code: 407, userInfo: [NSLocalizedDescriptionKey: "Package.swift is missing in active package dependencies."])
            }
        }

        // 8. Generated Project (Generate if workspace or xcodeproj doesn't exist)
        if !XcodeBuildAPI.shared.hasWorkspaceOrXcodeproj() {
            let projectName = metadata.projectName
            let schemeName = XcodeBuildAPI.shared.determineActiveScheme()?.name ?? projectName
            let success = await XcodeBuildAPI.shared.generateProjectWithXcodeGen(
                projectName: projectName,
                scheme: schemeName,
                bundleIdentifier: bundleID
            )
            if !success {
                throw NSError(domain: "PreviewBuild", code: 408, userInfo: [NSLocalizedDescriptionKey: "Failed to generate Xcode project via project generation pass."])
            }
        }
    }

    /// Automatically sets up a fresh live preview session by validating and building via XcodeBuildAPI.
    public func startFreshLivePreviewSession(
        sourcePath: String,
        sourceCode: String,
        targetViewName: String? = nil
    ) async {
        let requestID = UUID()
        self.currentSessionRequestID = requestID

        isCompiling = true
        buildLogs = ["Preview Session Started"]
        PreviewDiagnostics.shared.clearLogs()

        // 1. Clear previous runtime state, caches, and logs
        await stopActiveSession()
        PreviewCache.shared.clearCache()
        DocumentCoordinator.shared.compiledArtboardViews.removeAll()
        DocumentCoordinator.shared.compiledArtboardErrors.removeAll()

        // 2. Resolve Active metadata
        var activeProjName = "None"
        var activeSchemeName = "None"
        var buildConfigStr = "Debug"
        var isXcodeProj = false

        do {
            let metadata = try ProjectResolver.shared.resolveActiveProject()
            activeProjName = metadata.projectName
            isXcodeProj = metadata.isXcodeProject || metadata.isXcodeWorkspace || metadata.isSwiftPackage
            activeSchemeName = XcodeBuildAPI.shared.determineActiveScheme()?.name ?? metadata.projectName
            buildConfigStr = XcodeBuildAPI.shared.determineActiveBuildConfiguration().rawValue
        } catch {}

        // Discover modern #Preview targets
        let parsedTargets = PreviewBlockParser.parsePreviewTargets(in: sourceCode)
        let resolvedTarget = targetViewName ?? parsedTargets.first?.title ?? "ContentView"

        // 3. Create a brand-new session
        var session = PreviewSession(
            sessionID: UUID().uuidString,
            sourceFilePath: sourcePath,
            targetViewName: resolvedTarget,
            lastCompiledAt: Date(),
            status: "Initializing",
            state: .init_state,
            activeNodeHashes: [:]
        )
        session.activeProject = activeProjName
        session.activeScheme = activeSchemeName
        session.buildConfig = buildConfigStr
        session.previewTargets = parsedTargets

        self.activeSession = session
        self.availablePreviews = parsedTargets.isEmpty ? [resolvedTarget] : parsedTargets.map { $0.title }
        self.selectedPreviewName = resolvedTarget

        PreviewDiagnostics.shared.addLog(category: "state", message: "Preview Session Started")
        PreviewDiagnostics.shared.addLog(category: "engine", message: "Active Project Resolved: \(activeProjName)")
        PreviewDiagnostics.shared.addLog(category: "engine", message: "Scheme Resolved: \(activeSchemeName)")
        PreviewDiagnostics.shared.addLog(category: "engine", message: "Preview Target: \(resolvedTarget)")

        guard self.currentSessionRequestID == requestID else { return }

        // Synchronize parsed previews with artboards automatically
        synchronizeArtboardsForPreviews(sourcePath: sourcePath, sourceCode: sourceCode)

        // 4. Validation Pipeline
        do {
            session.state = .compiling
            session.status = "Validating..."
            self.activeSession = session
            PreviewDiagnostics.shared.addLog(category: "engine", message: "Validating build pipeline...")

            try await validatePreviewBuildPipeline()
            PreviewDiagnostics.shared.addLog(category: "engine", message: "Validation Succeeded.")

            guard self.currentSessionRequestID == requestID else { return }

            // 5. Build Project via XcodeBuildAPI if a real project is present
            if isXcodeProj {
                session.status = "Building via XcodeBuildAPI..."
                self.activeSession = session
                PreviewDiagnostics.shared.addLog(category: "compile", message: "Build Started via XcodeBuildAPI")

                let buildResult = await XcodeBuildAPI.shared.buildProject()
                session.buildResult = buildResult.status.rawValue
                self.activeSession = session

                guard self.currentSessionRequestID == requestID else { return }

                if buildResult.status != .succeeded {
                    // Extract structured diagnostics from compiler failures
                    var diagList: [PreviewDiagnosticModel] = []
                    for diag in buildResult.diagnostics {
                        diagList.append(PreviewDiagnosticModel(
                            stage: "XcodeBuild",
                            subsystem: "Compiler",
                            file: diag.filePath,
                            line: diag.line,
                            severity: diag.severity.rawValue,
                            description: diag.message,
                            suggestedFix: "Resolve the compiler warning or target error to proceed.",
                            rawCompilerOutput: buildResult.logs.lines.joined(separator: "\n")
                        ))
                    }

                    session.state = .failedNoPrior
                    session.status = "Build Failed"
                    session.diagnostics = diagList
                    self.activeSession = session

                    PreviewDiagnostics.shared.addLog(category: "error", message: "Project build failed.")
                    self.buildLogs = buildResult.logs.lines
                    self.hostedView = nil
                    isCompiling = false
                    return
                }

                // Compile succeeded
                PreviewDiagnostics.shared.addLog(category: "compile", message: "Build Finished Successfully.")
                session.compiledProduct = buildResult.appBundleURL
                self.activeSession = session
            }

            guard self.currentSessionRequestID == requestID else { return }

            // 6. Instantiating Preview & Rendering
            session.state = .rendering
            session.status = "Rendering..."
            self.activeSession = session
            PreviewDiagnostics.shared.addLog(category: "render", message: "Loading Dynamic Library...")

            let view = try await runtime.updateRuntimeSession(
                sourcePath: sourcePath,
                sourceCode: sourceCode,
                targetView: resolvedTarget
            ) { [weak self] message in
                guard let self = self else { return }
                Task { @MainActor in
                    self.buildLogs.append(message)
                }
            }

            guard self.currentSessionRequestID == requestID else { return }

            session.state = .rendered
            session.status = "Ready"
            self.activeSession = session
            self.hostedView = view

            PreviewDiagnostics.shared.addLog(category: "render", message: "Creating Hosting View")
            PreviewDiagnostics.shared.addLog(category: "render", message: "Rendering Artboard")
            PreviewDiagnostics.shared.addLog(category: "state", message: "Preview Complete")

        } catch {
            guard self.currentSessionRequestID == requestID else { return }

            let diagnostic = PreviewDiagnosticModel(
                stage: "Pipeline Validation",
                subsystem: "PreviewEngine",
                file: sourcePath,
                line: nil,
                severity: "error",
                description: error.localizedDescription,
                suggestedFix: "Ensure workspace configuration matches build guidelines.",
                rawCompilerOutput: error.localizedDescription
            )

            session.state = .failedNoPrior
            session.status = "Validation Failed"
            session.diagnostics = [diagnostic]
            self.activeSession = session
            self.hostedView = nil
            self.buildLogs = [error.localizedDescription]

            PreviewDiagnostics.shared.addLog(category: "error", message: error.localizedDescription)
            logger.error("Preview setup failed: \(error.localizedDescription)")
        }

        isCompiling = false
    }

    public func loadPreviews(forFileAt path: String, content: String) async {
        await startFreshLivePreviewSession(sourcePath: path, sourceCode: content)
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
        await startFreshLivePreviewSession(sourcePath: sourcePath, sourceCode: sourceCode, targetViewName: targetView)
    }

    public func refreshActiveSession(sourcePath: String, sourceCode: String, targetView: String) async {
        await startFreshLivePreviewSession(sourcePath: sourcePath, sourceCode: sourceCode, targetViewName: targetView)
    }

    public func startNewSession(sourcePath: String, sourceCode: String, targetView: String) async {
        await startFreshLivePreviewSession(sourcePath: sourcePath, sourceCode: sourceCode, targetViewName: targetView)
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
