import SwiftUI
import Observation
import os
import YcodeIDECore
import YcodeXcodebuild
import YcodePreviews
import YcodeSubprocess

@Observable
@MainActor
public final class PreviewManager {
    public static let shared = PreviewManager()

    public var activeSession: PreviewSession?
    public var secondarySessions: [String: PreviewSession] = [:]
    public var state = PreviewState()
    public var buildLogs: [String] = []
    public var availablePreviews: [String] = []
    public var selectedPreviewName: String?
    public var isCompiling = false
    public var hostedView: NSView?

    public var runtimeSessions: [UUID: RuntimeSession] = [:]

    public func getOrCreateRuntimeSession(for artboardID: UUID) -> RuntimeSession {
        if let session = runtimeSessions[artboardID] {
            return session
        }
        let session = RuntimeSession(artboardID: artboardID)
        runtimeSessions[artboardID] = session
        return session
    }

    private var currentSessionRequestID: UUID?

    private let runtime = PreviewRuntime.shared
    private let discoveryService = PreviewDiscoveryService()
    private let communicationService = PreviewCommunicationService()
    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "PreviewManager")

    private init() {}

    public func validatePreviewBuildPipeline() async throws {
        let metadata: ResolvedProjectMetadata
        do {
            let activeURL = XcodeBuildAPI.shared.discoverActiveProject()?.url ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            metadata = try ProjectResolver.resolveActiveProject(from: activeURL)
        } catch {
            throw NSError(domain: "PreviewBuild", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active workspace or project resolved."])
        }

        guard let _ = XcodeBuildAPI.shared.determineActiveProject() else {
            throw NSError(domain: "PreviewBuild", code: 402, userInfo: [NSLocalizedDescriptionKey: "Active target project not found."])
        }

        guard let _ = XcodeBuildAPI.shared.determineActiveScheme() else {
            throw NSError(domain: "PreviewBuild", code: 403, userInfo: [NSLocalizedDescriptionKey: "No active scheme selected for the target project."])
        }

        let bundleID = XcodeBuildAPI.shared.determineBundleIdentifier()
        if bundleID.isEmpty {
            throw NSError(domain: "PreviewBuild", code: 404, userInfo: [NSLocalizedDescriptionKey: "Bundle identifier is invalid or empty."])
        }

        let fm = FileManager.default
        let hasSwiftc = fm.fileExists(atPath: "/usr/bin/swiftc") || fm.fileExists(atPath: "/usr/bin/swift")
        if !hasSwiftc {
            throw NSError(domain: "PreviewBuild", code: 405, userInfo: [NSLocalizedDescriptionKey: "Swift compiler tools (swiftc) are missing in the current system."])
        }

        let validation = await XcodeBuildAPI.shared.validateBuildEnvironment()
        if !validation.isValid {
            throw NSError(domain: "PreviewBuild", code: 406, userInfo: [NSLocalizedDescriptionKey: validation.errorDescription ?? "Build environment SDK validation failed."])
        }

        if metadata.kind == .package {
            let packageURL = metadata.url.appendingPathComponent("Package.swift")
            guard fm.fileExists(atPath: packageURL.path) else {
                throw NSError(domain: "PreviewBuild", code: 407, userInfo: [NSLocalizedDescriptionKey: "Package.swift is missing in active package dependencies."])
            }
        }

        if !XcodeBuildAPI.shared.hasWorkspaceOrXcodeproj() {
            let projectName = metadata.name
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

        await stopActiveSession()
        await PreviewCache.shared.clearAll()
        DocumentCoordinator.shared.compiledArtboardViews.removeAll()
        DocumentCoordinator.shared.compiledArtboardErrors.removeAll()

        var activeProjName = "None"
        var activeSchemeName = "None"
        var buildConfigStr = "Debug"
        var isXcodeProj = false

        do {
            let metadata = try ProjectResolver.resolveActiveProject(from: URL(fileURLWithPath: sourcePath))
            activeProjName = metadata.name
            isXcodeProj = true
            activeSchemeName = XcodeBuildAPI.shared.determineActiveScheme()?.name ?? metadata.name
            buildConfigStr = XcodeBuildAPI.shared.determineActiveBuildConfiguration()
        } catch {}

        let parsedTargets = PreviewBlockParser.parsePreviewTargets(in: sourceCode)
        let resolvedTarget = targetViewName ?? parsedTargets.first?.title ?? "ContentView"

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

        synchronizeArtboardsForPreviews(sourcePath: sourcePath, sourceCode: sourceCode)

        do {
            session.state = .compiling
            session.status = "Validating..."
            self.activeSession = session
            PreviewDiagnostics.shared.addLog(category: "engine", message: "Validating build pipeline...")

            try await validatePreviewBuildPipeline()
            PreviewDiagnostics.shared.addLog(category: "engine", message: "Validation Succeeded.")

            guard self.currentSessionRequestID == requestID else { return }

            if isXcodeProj {
                session.status = "Building via XcodeBuildAPI..."
                self.activeSession = session
                PreviewDiagnostics.shared.addLog(category: "compile", message: "Build Started via XcodeBuildAPI")

                let buildResult = await XcodeBuildAPI.shared.buildProject()
                session.buildResult = buildResult.status.rawValue
                self.activeSession = session

                guard self.currentSessionRequestID == requestID else { return }

                if buildResult.status != .succeeded {
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

                PreviewDiagnostics.shared.addLog(category: "compile", message: "Build Finished Successfully.")
                session.compiledProduct = buildResult.appBundleURL
                self.activeSession = session
            }

            guard self.currentSessionRequestID == requestID else { return }

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

    public func stopAndRestartSession() async {
        XcodeBuildAPI.shared.cancelBuild()
        FullAppRunManager.shared.stopApplication()
        runtime.stopRuntime()

        #if os(macOS)
        do {
            _ = try await ProcessRunnerTool.shared.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/killall"),
                arguments: ["-9", "swiftc"]
            )
        } catch {}
        do {
            _ = try await ProcessRunnerTool.shared.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/killall"),
                arguments: ["-9", "xcodebuild"]
            )
        } catch {}
        #endif

        self.activeSession = nil
        self.hostedView = nil
        self.secondarySessions.removeAll()
        self.buildLogs.removeAll()

        await PreviewCache.shared.clearAll()
        DocumentCoordinator.shared.compiledArtboardViews.removeAll()
        DocumentCoordinator.shared.compiledArtboardErrors.removeAll()

        if let doc = DocumentCoordinator.shared.activeDocument, let docURL = doc.fileURL {
            let content = (try? String(contentsOf: docURL, encoding: .utf8)) ?? ""
            let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(content, filename: docURL.path)
            await startFreshLivePreviewSession(sourcePath: docURL.path, sourceCode: preparedCode)
        } else if let visDoc = DocumentCoordinator.shared.visualUIDocument,
                  let activeID = visDoc.scene.activeArtboardID,
                  let activeArtboard = visDoc.scene.artboards.first(where: { $0.id == activeID }),
                  let customSource = activeArtboard.customSwiftUISource, !customSource.isEmpty {
            let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(customSource, filename: "Artboard_\(activeArtboard.id).swift")
            await startFreshLivePreviewSession(sourcePath: "Artboard_\(activeArtboard.id).swift", sourceCode: preparedCode)
        }
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
