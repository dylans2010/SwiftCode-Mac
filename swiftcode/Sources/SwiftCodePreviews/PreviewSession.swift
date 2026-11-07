import Foundation
import Observation
import SwiftCodeSubprocess

public enum PreviewSessionState: String, Codable, Sendable {
    case init_state = "INIT"
    case sourceReceived = "SOURCE_RECEIVED"
    case discovering = "DISCOVERING"
    case noCandidates = "NO_CANDIDATES"
    case compiling = "COMPILING"
    case rendering = "RENDERING"
    case rendered = "RENDERED"
    case failedKeepLast = "FAILED_KEEP_LAST"
    case failedNoPrior = "FAILED_NO_PRIOR"
}

public struct PreviewDiagnosticModel: Sendable, Codable, Identifiable, Hashable {
    public var id: UUID { UUID() }
    public let stage: String
    public let subsystem: String
    public let file: String?
    public let line: Int?
    public let severity: String
    public let description: String
    public let suggestedFix: String?
    public let rawCompilerOutput: String

    public init(
        stage: String,
        subsystem: String,
        file: String?,
        line: Int?,
        severity: String,
        description: String,
        suggestedFix: String?,
        rawCompilerOutput: String
    ) {
        self.stage = stage
        self.subsystem = subsystem
        self.file = file
        self.line = line
        self.severity = severity
        self.description = description
        self.suggestedFix = suggestedFix
        self.rawCompilerOutput = rawCompilerOutput
    }
}

public struct PreviewTarget: Sendable, Codable, Hashable, Identifiable {
    public var id: String { title }
    public let title: String
    public let rootView: String
    public let device: String?
    public let traits: String?

    public init(title: String, rootView: String, device: String?, traits: String?) {
        self.title = title
        self.rootView = rootView
        self.device = device
        self.traits = traits
    }
}

public struct PreviewSession: Identifiable, Hashable, Codable, Sendable {
    public var id: String { sessionID }
    public let sessionID: String
    public let sourceFilePath: String
    public let targetViewName: String
    public var lastCompiledAt: Date
    public var status: String
    public var state: PreviewSessionState
    public var activeNodeHashes: [String: Int]

    public var activeProject: String = "None"
    public var activeScheme: String = "None"
    public var buildConfig: String = "Debug"
    public var previewTargets: [PreviewTarget] = []
    public var diagnostics: [PreviewDiagnosticModel] = []
    public var logs: [String] = []
    public var buildResult: String? = nil
    public var compiledProduct: URL? = nil

    public init(
        sessionID: String,
        sourceFilePath: String,
        targetViewName: String,
        lastCompiledAt: Date = Date(),
        status: String = "Idle",
        state: PreviewSessionState = .init_state,
        activeNodeHashes: [String: Int] = [:]
    ) {
        self.sessionID = sessionID
        self.sourceFilePath = sourceFilePath
        self.targetViewName = targetViewName
        self.lastCompiledAt = lastCompiledAt
        self.status = status
        self.state = state
        self.activeNodeHashes = activeNodeHashes
    }

    public func hasNodeChanged(id: String, hash: Int) -> Bool {
        return activeNodeHashes[id] != hash
    }
}

@Observable
@MainActor
public final class RuntimeSession: Identifiable, Sendable {
    public let id = UUID()
    public let artboardID: UUID
    public var status: String = "Idle"
    public var buildDuration: TimeInterval = 0.0
    public var elapsedRuntime: TimeInterval = 0.0
    public var logs: [String] = []
    public var diagnostics: [PreviewDiagnosticModel] = []
    public var isExecuting: Bool = false
    public var isRunning: Bool = false
    public var healthStatus: String = "Healthy"
    public var projectName: String = "Unknown"
    public var schemeName: String = "Unknown"
    public var buildConfig: String = "Debug"
    public var sdk: String = "macosx"
    public var destination: String = "Mac"
    public var compiledProduct: URL?

    private var durationTimer: Timer?
    private var runtimeTimer: Timer?

    public init(artboardID: UUID) {
        self.artboardID = artboardID
    }

    public func startBuildPipeline(projectDirectory: URL, sourceFile: URL, targetViewName: String? = nil, deploymentTarget: String? = nil) async {
        isExecuting = true
        status = "Validating Project..."
        logs = ["[PIPELINE] Validation stage started."]
        diagnostics = []
        buildDuration = 0
        elapsedRuntime = 0
        isRunning = false
        healthStatus = "Healthy"
        compiledProduct = nil

        startBuildTimer()
        let buildStarted = Date()

        do {
            status = "Resolving Entry..."
            logs.append("[PIPELINE] Scanning project and resolving the preview entry...")
            let structure = try await PreviewProjectScanner().scan(projectDirectory: projectDirectory)
            let entry = try PreviewEntryResolver().resolve(projectStructure: structure, preferredView: targetViewName)
            projectName = entry.appName
            schemeName = entry.rootViewType
            logs.append("[PIPELINE] Entry Resolved:")
            logs.append("  - App: \(entry.appName)")
            logs.append("  - Root View: \(entry.rootViewType)")
            logs.append("  - Scene: \(entry.sceneType)")

            status = "Generating Payload..."
            let sourceText = (try? String(contentsOf: sourceFile, encoding: .utf8)) ?? ""
            let previewed = PreviewedFile(url: sourceFile, previews: PreviewDiscovery.previews(in: sourceText))
            let payloadDir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-preview-\(UUID().uuidString)")
            let sources = try PreviewPayloadGenerator.generate(
                moduleFiles: structure.swiftFiles, previewed: [previewed], platform: .macOS, into: payloadDir)

            status = "Compiling Project..."
            logs.append("[PIPELINE] Compiling the preview payload...")
            let output = payloadDir.appendingPathComponent("Preview.dylib")
            let target = PreviewMacHost.deploymentTarget(sdkVersion: deploymentTarget ?? Self.macSDKVersion())
            let compiler = PreviewCompiler(platform: .macOS, deploymentTarget: target, moduleName: "Preview", moduleCache: payloadDir)
            do {
                try compiler.compilePayload(sources, output: output)
            } catch let failure as PreviewFailure {
                stopBuildTimer()
                status = "Compilation Failed"
                isExecuting = false
                diagnostics = Self.diagnostics(from: failure)
                for diag in diagnostics { logs.append("[COMPILER ERROR] \(diag.description)") }
                logs.append("[PIPELINE] Compilation failed.")
                return
            }

            compiledProduct = output
            await PreviewCache.shared.setBinary(output, forSourcePath: sourceFile.path)
            PreviewPerformanceMonitor.shared.recordRenderTime(Date().timeIntervalSince(buildStarted))
            stopBuildTimer()

            status = "Launching Runtime..."
            logs.append("[PIPELINE] Build Succeeded!")
            logs.append("[PIPELINE] Compiled preview module: \(output.lastPathComponent)")

            isExecuting = false
            isRunning = true
            startRuntimeTimer()
            logs.append("[RUNTIME] Preview runtime attached.")
        } catch {
            stopBuildTimer()
            status = "Validation Failed"
            isExecuting = false
            diagnostics = [
                PreviewDiagnosticModel(
                    stage: "Pipeline Validation",
                    subsystem: "PreviewEngine",
                    file: nil,
                    line: nil,
                    severity: "error",
                    description: error.localizedDescription,
                    suggestedFix: "Ensure workspace configuration matches build guidelines.",
                    rawCompilerOutput: error.localizedDescription
                )
            ]
            logs.append("[PIPELINE ERROR] Setup failed: \(error.localizedDescription)")
        }
    }

    private static func diagnostics(from failure: PreviewFailure) -> [PreviewDiagnosticModel] {
        switch failure {
        case .compile(let issues):
            if issues.isEmpty {
                return [PreviewDiagnosticModel(
                    stage: "Compiler", subsystem: "PreviewCompiler", file: "Build Logs", line: nil,
                    severity: "error", description: "Compilation task failed. Review the raw console logs below.",
                    suggestedFix: "Run a 'Clean Build Folder' pass and build again.",
                    rawCompilerOutput: failure.description)]
            }
            return issues.map { issue in
                PreviewDiagnosticModel(
                    stage: "Compiler", subsystem: "PreviewCompiler",
                    file: issue.file?.path ?? "Active Document",
                    line: issue.line == 0 ? nil : issue.line,
                    severity: "error", description: issue.message,
                    suggestedFix: "Check code syntax or package import statements.",
                    rawCompilerOutput: issue.description)
            }
        case .host(let message):
            return [PreviewDiagnosticModel(
                stage: "Compiler", subsystem: "PreviewCompiler", file: nil, line: nil,
                severity: "error", description: message,
                suggestedFix: "Ensure the preview toolchain is installed.",
                rawCompilerOutput: message)]
        case .unsupported(let message):
            return [PreviewDiagnosticModel(
                stage: "Compiler", subsystem: "PreviewCompiler", file: nil, line: nil,
                severity: "error", description: message,
                suggestedFix: "Preview is unsupported for this target.",
                rawCompilerOutput: message)]
        }
    }

    public func stop() {
        stopRuntimeTimer()
        isRunning = false
        status = "Stopped"
        logs.append("[SYSTEM] Runtime session halted.")
    }

    public func restart(projectDirectory: URL, sourceFile: URL, targetViewName: String? = nil) {
        stop()
        Task {
            await startBuildPipeline(projectDirectory: projectDirectory, sourceFile: sourceFile, targetViewName: targetViewName)
        }
    }

    private static func macSDKVersion() -> String {
        let version = (try? Subprocess.run("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-version"]))?.stdoutText
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return version.isEmpty ? "15.0" : version
    }

    private func startBuildTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.buildDuration += 0.1
            }
        }
    }

    private func stopBuildTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func startRuntimeTimer() {
        runtimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.elapsedRuntime += 1.0
            }
        }
    }

    private func stopRuntimeTimer() {
        runtimeTimer?.invalidate()
        runtimeTimer = nil
    }
}
