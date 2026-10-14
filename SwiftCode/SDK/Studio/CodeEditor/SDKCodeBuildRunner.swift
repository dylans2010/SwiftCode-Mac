import CryptoKit
import Darwin
import Foundation

// MARK: - SDKCodeBuildRunner
//
// Executes `SDKBuildRunRequest`s for real, validates `swiftcode.json` and
// capability declarations against source files, parses structured compiler
// diagnostics (TypeScript `tsc` and Swift/Clang `xcodebuild`), and streams
// stdout/stderr into the editor console LIVE, line by line, via
// `SDKCodeEditorState.appendConsole(_:)`.

public actor SDKCodeBuildRunner {
    public static let shared = SDKCodeBuildRunner()

    /// Host-owned identity the Studio editor presents to the managed build
    /// service. Distinct from every extension ID, so the service's
    /// one-build-per-extension slot never collides with extension builds.
    public static let hostExtensionID = "studio.editor"

    /// Stable digest for the host identity.
    public static let hostPackageDigest: String = {
        let digest = SHA256.hash(data: Data("swiftcode.sdk.studio.editor".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }()

    /// Pinned executable lookup for local (npm/node) runs.
    private static let envExecutablePath = "/usr/bin/env"

    /// Grace period between SIGTERM and SIGKILL when cancelling a local
    /// (npm/node) process that ignores termination.
    private static let cancelGraceNanoseconds: UInt64 = 3_000_000_000

    private enum ActiveEntry {
        case managedBuild(SDKBuildHandle)
        case localProcess(LocalProcessSession)
    }

    private var active: [UUID: ActiveEntry] = [:]

    public init() {}

    // MARK: - Public API

    /// Validates the project at `projectRoot` (manifest schema, semantic rules,
    /// capability declarations vs. source usage, and entrypoints) and populates
    /// `editorState.diagnostics`. Returns `true` when zero errors are found.
    @discardableResult
    public func validateProject(at projectRoot: URL, into editorState: SDKCodeEditorState) async -> Bool {
        await editorState.saveAllModifiedTabs()
        await editorState.clearDiagnostics()

        let root = projectRoot.standardizedFileURL
        let manifestURL = root.appendingPathComponent("swiftcode.json")
        let fm = FileManager.default

        await emit(.system("Validating project at \(root.lastPathComponent)…"), to: editorState)

        guard fm.fileExists(atPath: manifestURL.path) else {
            // Standalone project without swiftcode.json: check basic structure.
            let packageJSON = root.appendingPathComponent("package.json")
            let swiftFiles = (try? fm.contentsOfDirectory(atPath: root.path))?.filter { $0.hasSuffix(".swift") || $0.hasSuffix(".xcodeproj") } ?? []
            if !fm.fileExists(atPath: packageJSON.path) && swiftFiles.isEmpty {
                let diag = SDKEditorDiagnostic(
                    severity: .warning,
                    source: "project",
                    code: "NO_MANIFEST_OR_PROJECT",
                    message: "No swiftcode.json, package.json, or Swift project found in \(root.lastPathComponent).",
                    suggestion: "Open an extension or project root directory.",
                    fileURL: root,
                    line: 1
                )
                await editorState.appendDiagnostic(diag)
                await emit(.stderr("[WARN] \(diag.message)"), to: editorState)
            } else {
                await emit(.system("Standalone project structure verified (no swiftcode.json manifest)."), to: editorState)
            }
            return true
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            let diag = SDKEditorDiagnostic(
                severity: .error,
                source: "swiftcode.json",
                code: "MANIFEST_READ_ERROR",
                message: "Could not read swiftcode.json: \(error.localizedDescription)",
                fileURL: manifestURL,
                line: 1
            )
            await editorState.appendDiagnostic(diag)
            await emit(.stderr("[ERROR] \(diag.message)"), to: editorState)
            return false
        }

        // For pre-build validation we validate structural/semantic rules and capability registry membership;
        // runtime entrypoint existence is checked as a warning before build (since `npm run build` produces `dist/index.js`).
        let manifest = try? SDKManifestValidator.validate(data: data)
        let rawDiagnostics = SDKManifestValidator.validateWithDiagnostics(
            data: data,
            projectRoot: nil,
            grantedCapabilities: nil
        )

        var errorCount = 0
        var warningCount = 0

        for item in rawDiagnostics {
            let sev: SDKEditorDiagnostic.Severity
            switch item.severity {
            case .error:
                sev = .error
                errorCount += 1
            case .warning:
                sev = .warning
                warningCount += 1
            case .info:
                sev = .info
            }
            let editorDiag = SDKEditorDiagnostic(
                severity: sev,
                source: "swiftcode.json",
                code: item.field,
                message: item.message,
                suggestion: item.suggestion,
                fileURL: manifestURL,
                line: item.line ?? 1
            )
            await editorState.appendDiagnostic(editorDiag)
            let prefix = sev == .error ? "[ERROR]" : (sev == .warning ? "[WARN]" : "[INFO]")
            await emit(
                sev == .error ? .stderr("\(prefix) swiftcode.json:\(item.line ?? 1) — \(item.message)") : .system("\(prefix) swiftcode.json:\(item.line ?? 1) — \(item.message)"),
                to: editorState
            )
        }

        // Cross-check source capability references against declared manifest capabilities.
        if let manifest {
            let declaredIDs = Set(manifest.capabilities.map(\.id))
            let sourceDiags = Self.scanSourceCapabilityUsage(in: root, declaredCapabilities: declaredIDs)
            for diag in sourceDiags {
                if diag.severity == .error { errorCount += 1 }
                if diag.severity == .warning { warningCount += 1 }
                await editorState.appendDiagnostic(diag)
                let fileLabel = diag.fileURL?.lastPathComponent ?? "source"
                await emit(
                    .stderr("[WARN] \(fileLabel):\(diag.line ?? 1) — \(diag.message)"),
                    to: editorState
                )
            }
        }

        if errorCount == 0 {
            await emit(
                .system("Validation passed (0 errors, \(warningCount) warning(s))."),
                to: editorState
            )
            return true
        } else {
            await emit(
                .stderr("Validation failed with \(errorCount) error(s) and \(warningCount) warning(s)."),
                to: editorState
            )
            return false
        }
    }

    /// Executes `request` for real, streaming output lines into
    /// `editorState` as they arrive. Does not return until the run reaches
    /// a terminal state (or the request fails to start); the caller keeps
    /// `request.taskID` and uses `cancel(taskID:)` to stop it early.
    public func run(_ request: SDKBuildRunRequest, into editorState: SDKCodeEditorState) async {
        guard active[request.taskID] == nil else {
            await emit(.system("Build/run ignored: task \(request.taskID.uuidString) is already in flight."), to: editorState)
            return
        }

        await editorState.saveAllModifiedTabs()
        await editorState.clearDiagnostics()

        let manifestURL = request.projectRoot.appendingPathComponent("swiftcode.json")
        if request.kind == .typescriptExtension || FileManager.default.fileExists(atPath: manifestURL.path) {
            let valid = await validateProject(at: request.projectRoot, into: editorState)
            if !valid {
                await emit(.stderr("Build aborted: fix swiftcode.json validation errors before building."), to: editorState)
                return
            }
        }

        switch request.kind {
        case .xcodebuildSwift:
            await runManagedBuild(request, into: editorState)
        case .typescriptExtension, .nodeScript:
            await runLocalProcess(request, into: editorState)
        }
    }

    /// Genuine cancellation: terminates the underlying build handle or
    /// process for `taskID`.
    public func cancel(taskID: UUID) async {
        guard let entry = active[taskID] else { return }
        switch entry {
        case .managedBuild(let handle):
            await handle.cancel()
        case .localProcess(let session):
            await session.requestCancel()
        }
    }

    /// Whether `taskID` currently has a run in flight.
    public func isRunning(taskID: UUID) -> Bool {
        active[taskID] != nil
    }

    // MARK: - Managed xcodebuild path

    private func runManagedBuild(_ request: SDKBuildRunRequest, into editorState: SDKCodeEditorState) async {
        let taskID = request.taskID
        let scheme = request.schemeOrEntry?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sdkRequest = SDKBuildRequest(target: scheme)
        let caller = SDKCallerIdentity(
            extensionID: Self.hostExtensionID,
            packageDigest: Self.hostPackageDigest,
            projectRootPath: request.projectRoot.path,
            apiKey: nil
        )
        await emit(
            .system("Build requested (xcodebuild) — project: \(request.projectRoot.lastPathComponent), scheme: \(scheme.isEmpty ? "<auto-detect>" : "\"\(scheme)\"")"),
            to: editorState
        )

        let handle: SDKBuildHandle
        do {
            handle = try await SDKBuildService.shared.run(request: sdkRequest, caller: caller)
        } catch let sdkError as SDKError {
            var text = "Build could not start [\(sdkError.code.rawValue)]: \(sdkError.message)"
            if let suggestion = sdkError.suggestion, !suggestion.isEmpty {
                text += " \(suggestion)"
            }
            let diag = SDKEditorDiagnostic(
                severity: .error,
                source: "xcodebuild",
                code: sdkError.code.rawValue,
                message: sdkError.message,
                suggestion: sdkError.suggestion,
                fileURL: request.projectRoot,
                line: 1
            )
            await editorState.appendDiagnostic(diag)
            await emit(.system(text), to: editorState)
            return
        } catch {
            await emit(.system("Build could not start: \(error.localizedDescription)"), to: editorState)
            return
        }
        active[taskID] = .managedBuild(handle)

        for await event in await handle.events() {
            if let diag = Self.parseCompilerDiagnostic(line: event.text, projectRoot: request.projectRoot) {
                await editorState.appendDiagnostic(diag)
            }
            await emit(consoleEntry(for: event), to: editorState)
        }
        let result: SDKBuildResult
        do {
            result = try await handle.wait()
        } catch {
            active[taskID] = nil
            await emit(.system("Build result unavailable: \(error.localizedDescription)"), to: editorState)
            return
        }
        active[taskID] = nil
        await emit(terminalEntry(for: result), to: editorState)
    }

    private func consoleEntry(for event: SDKBuildOutputEvent) -> SDKConsoleEntry {
        switch event.kind {
        case .stdout: return .stdout(event.text)
        case .stderr: return .stderr(event.text)
        case .status: return .system(event.text)
        }
    }

    private func terminalEntry(for result: SDKBuildResult) -> SDKConsoleEntry {
        let duration = String(format: "%.1f", result.durationSeconds)
        switch result.status {
        case .succeeded:
            return .system("Build succeeded in \(duration)s.")
        case .failed:
            let exit = result.exitCode.map(String.init) ?? "?"
            return .system("Build failed (exit \(exit), \(result.errorCount) error(s), \(result.warningCount) warning(s), \(duration)s).")
        case .cancelled:
            return .system("Build cancelled.")
        case .timedOut:
            return .system("Build timed out after 30 minutes.")
        case .running:
            return .system("Build ended in an unexpected state (still marked running).")
        }
    }

    // MARK: - Local process path (npm / node)

    private func runLocalProcess(_ request: SDKBuildRunRequest, into editorState: SDKCodeEditorState) async {
        let taskID = request.taskID
        let root = request.projectRoot

        // If building a TypeScript extension/project and node_modules does not exist yet, run `npm install` first.
        if request.kind == .typescriptExtension {
            let nodeModules = root.appendingPathComponent("node_modules")
            let packageJSON = root.appendingPathComponent("package.json")
            if FileManager.default.fileExists(atPath: packageJSON.path),
               !FileManager.default.fileExists(atPath: nodeModules.path) {
                await emit(.system("Installing dependencies (npm install)…"), to: editorState)
                let installSession = LocalProcessSession(
                    executable: URL(fileURLWithPath: Self.envExecutablePath),
                    arguments: ["npm", "install", "--no-audit", "--no-fund"],
                    workingDirectory: root
                ) { [weak self] entry in
                    guard let self else { return }
                    Task { await self.emit(entry, to: editorState) }
                }
                if (try? await installSession.launch()) != nil {
                    active[taskID] = .localProcess(installSession)
                    let installOutcome = await installSession.waitForExit()
                    active[taskID] = nil
                    if installOutcome.cancelled {
                        await emit(.system("npm install — cancelled."), to: editorState)
                        return
                    }
                }
            }
        }

        let arguments: [String]
        let label: String
        switch request.kind {
        case .typescriptExtension:
            arguments = ["npm", "run", "build"]
            label = "npm run build"
        case .nodeScript:
            guard let raw = request.schemeOrEntry?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                await emit(.system("Run failed: no script path provided."), to: editorState)
                return
            }
            guard let scriptURL = Self.scriptURL(for: raw, under: root) else {
                await emit(.system("Run failed: script path \"\(raw)\" escapes the project root."), to: editorState)
                return
            }
            arguments = ["node", scriptURL.path]
            label = "node \(raw)"
        case .xcodebuildSwift:
            return
        }

        let startedAt = Date()
        await emit(.system("\(label) — started in \(root.lastPathComponent)"), to: editorState)

        let session: LocalProcessSession
        do {
            session = LocalProcessSession(
                executable: URL(fileURLWithPath: Self.envExecutablePath),
                arguments: arguments,
                workingDirectory: root
            ) { [weak self] entry in
                guard let self else { return }
                Task {
                    if let diag = Self.parseCompilerDiagnostic(line: entry.text, projectRoot: root) {
                        await editorState.appendDiagnostic(diag)
                    }
                    await self.emit(entry, to: editorState)
                }
            }
            try await session.launch()
        } catch {
            await emit(.system("\(label) — could not start: \(error.localizedDescription)"), to: editorState)
            return
        }
        active[taskID] = .localProcess(session)

        let outcome = await session.waitForExit()
        active[taskID] = nil

        let duration = String(format: "%.1f", Date().timeIntervalSince(startedAt))
        if outcome.cancelled {
            await emit(.system("\(label) — cancelled."), to: editorState)
        } else if outcome.reason == .exit, outcome.exitCode == 0 {
            // Post-build entrypoint verification for extensions with swiftcode.json
            let manifestURL = root.appendingPathComponent("swiftcode.json")
            if request.kind == .typescriptExtension,
               let data = try? Data(contentsOf: manifestURL),
               let manifest = try? JSONDecoder().decode(SDKManifest.self, from: data) {
                let entryURL = root.appendingPathComponent(manifest.runtime.entrypoint)
                if !FileManager.default.fileExists(atPath: entryURL.path) {
                    let diag = SDKEditorDiagnostic(
                        severity: .error,
                        source: "runtime.entrypoint",
                        code: "ENTRYPOINT_NOT_BUILT",
                        message: "Build exited 0, but runtime entrypoint \"\(manifest.runtime.entrypoint)\" was not produced.",
                        suggestion: "Ensure tsconfig.json outDir and rootDir output to \(manifest.runtime.entrypoint).",
                        fileURL: manifestURL,
                        line: 1
                    )
                    await editorState.appendDiagnostic(diag)
                    await emit(.stderr("[ERROR] \(diag.message)"), to: editorState)
                    return
                }
            }
            await emit(.system("\(label) — finished successfully (exit 0, \(duration)s)."), to: editorState)
        } else if outcome.reason == .exit {
            await emit(.system("\(label) — failed with exit code \(outcome.exitCode) (\(duration)s)."), to: editorState)
        } else {
            await emit(.system("\(label) — terminated by signal \(outcome.exitCode) (\(duration)s)."), to: editorState)
        }
    }

    private static func scriptURL(for entry: String, under root: URL) -> URL? {
        let base = root.standardized
        let candidate = base.appendingPathComponent(entry).standardized
        let basePath = base.path
        guard candidate.path == basePath || candidate.path.hasPrefix(basePath + "/") else {
            return nil
        }
        return candidate
    }

    // MARK: - Compiler & Source Diagnostic Parsing

    /// Parses a single output line from `tsc` or `swiftc`/`xcodebuild` into a structured `SDKEditorDiagnostic`.
    public nonisolated static func parseCompilerDiagnostic(line: String, projectRoot: URL) -> SDKEditorDiagnostic? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. TypeScript `tsc` format: `src/index.ts(12,5): error TS2322: Message`
        if let match = trimmed.firstMatch(of: #/^(.+?)\((\d+),(\d+)\):\s*(error|warning)\s+(TS\d+):\s*(.+)$/#) {
            let relPath = String(match.1)
            let lineNum = Int(match.2) ?? 1
            let colNum = Int(match.3) ?? 1
            let sev: SDKEditorDiagnostic.Severity = match.4 == "error" ? .error : .warning
            let code = String(match.5)
            let msg = String(match.6)
            let fileURL = resolveFileURL(relPath, under: projectRoot)
            return SDKEditorDiagnostic(
                severity: sev,
                source: "tsc",
                code: code,
                message: msg,
                fileURL: fileURL,
                line: lineNum,
                column: colNum
            )
        }

        // 2. TypeScript pretty format: `src/index.ts:12:5 - error TS2322: Message`
        if let match = trimmed.firstMatch(of: #/^(.+?):(\d+):(\d+)\s*-\s*(error|warning)\s+(TS\d+):\s*(.+)$/#) {
            let relPath = String(match.1)
            let lineNum = Int(match.2) ?? 1
            let colNum = Int(match.3) ?? 1
            let sev: SDKEditorDiagnostic.Severity = match.4 == "error" ? .error : .warning
            let code = String(match.5)
            let msg = String(match.6)
            let fileURL = resolveFileURL(relPath, under: projectRoot)
            return SDKEditorDiagnostic(
                severity: sev,
                source: "tsc",
                code: code,
                message: msg,
                fileURL: fileURL,
                line: lineNum,
                column: colNum
            )
        }

        // 3. Swift / Clang format: `/path/to/File.swift:42:10: error: Message`
        if let match = trimmed.firstMatch(of: #/^(.+\.(?:swift|m|mm|c|cpp|h|ts|js)):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$/#) {
            let rawPath = String(match.1)
            let lineNum = Int(match.2) ?? 1
            let colNum = Int(match.3) ?? 1
            let sevStr = String(match.4)
            let sev: SDKEditorDiagnostic.Severity = sevStr == "error" ? .error : (sevStr == "warning" ? .warning : .info)
            let msg = String(match.5)
            let fileURL = resolveFileURL(rawPath, under: projectRoot)
            return SDKEditorDiagnostic(
                severity: sev,
                source: "swiftc",
                code: sevStr.uppercased(),
                message: msg,
                fileURL: fileURL,
                line: lineNum,
                column: colNum
            )
        }

        return nil
    }

    private nonisolated static func resolveFileURL(_ path: String, under root: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return root.appendingPathComponent(path).standardizedFileURL
    }

    /// Scans TypeScript source files under `src/` for capability IDs or SDK namespace calls that
    /// are not declared in `swiftcode.json`, returning actionable warnings with line numbers.
    private nonisolated static func scanSourceCapabilityUsage(
        in projectRoot: URL,
        declaredCapabilities: Set<String>
    ) -> [SDKEditorDiagnostic] {
        let srcDir = projectRoot.appendingPathComponent("src")
        guard let enumerator = FileManager.default.enumerator(
            at: srcDir,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let namespaceRules: [(pattern: String, requiredAny: [String], label: String)] = [
            ("sdk.sourceControl.status", ["source-control.read", "use.SourceControl"], "sdk.sourceControl.status()"),
            ("sdk.sourceControl.diff", ["source-control.read", "use.SourceControl"], "sdk.sourceControl.diff()"),
            ("sdk.sourceControl.log", ["source-control.read", "use.SourceControl"], "sdk.sourceControl.log()"),
            ("sdk.build.run", ["build.execute"], "sdk.build.run()"),
            ("sdk.filesystem.read", ["filesystem.read", "use.Files"], "sdk.filesystem.read()"),
            ("sdk.filesystem.write", ["filesystem.write", "use.Files"], "sdk.filesystem.write()"),
            ("sdk.network.fetch", ["network.outbound"], "sdk.network.fetch()"),
            ("sdk.secrets.get", ["secrets.read", "use.Security"], "sdk.secrets.get()"),
            ("sdk.terminal.", ["use.Terminal"], "sdk.terminal"),
            ("sdk.XcodeBuild.", ["use.XcodeBuild"], "sdk.XcodeBuild"),
            ("sdk.Assist.", ["use.Assist"], "sdk.Assist"),
            ("sdk.Security.", ["use.Security"], "sdk.Security")
        ]

        var results: [SDKEditorDiagnostic] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "ts" || fileURL.pathExtension == "js" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }
                for rule in namespaceRules where line.contains(rule.pattern) {
                    let hasDeclaration = rule.requiredAny.contains { declaredCapabilities.contains($0) }
                    if !hasDeclaration {
                        let primaryCap = rule.requiredAny[0]
                        results.append(SDKEditorDiagnostic(
                            severity: .warning,
                            source: "capability-audit",
                            code: "UNDECLARED_CAPABILITY_USAGE",
                            message: "\(rule.label) requires capability \"\(primaryCap)\" in swiftcode.json.",
                            suggestion: "Add \"\(primaryCap)\" to capabilities in swiftcode.json.",
                            fileURL: fileURL.standardizedFileURL,
                            line: idx + 1,
                            column: 1
                        ))
                    }
                }
            }
        }
        return results
    }

    // MARK: - Console sink

    private func emit(_ entry: SDKConsoleEntry, to editorState: SDKCodeEditorState) async {
        await editorState.appendConsole(entry)
    }

    // MARK: - LocalProcessSession

    private actor LocalProcessSession {
        typealias LineSink = @Sendable (SDKConsoleEntry) -> Void

        private let process: Process
        private let stdoutHandle: FileHandle
        private let stderrHandle: FileHandle
        private let onLine: LineSink

        private var stdoutRemainder = ""
        private var stderrRemainder = ""
        private var cancelRequested = false
        private var finished = false

        init(
            executable: URL,
            arguments: [String],
            workingDirectory: URL,
            onLine: @escaping LineSink
        ) {
            self.onLine = onLine
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            var env = ProcessInfo.processInfo.environment
            let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            var pathParts = existingPath.components(separatedBy: ":")
            for extra in ["/opt/homebrew/bin", "/usr/local/bin"] where !pathParts.contains(extra) {
                pathParts.insert(extra, at: 0)
            }
            env["PATH"] = pathParts.joined(separator: ":")
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            self.process = process
            self.stdoutHandle = stdoutPipe.fileHandleForReading
            self.stderrHandle = stderrPipe.fileHandleForReading
        }

        func launch() throws {
            stdoutHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self else { return }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    Task { await self.ingest(data: data, stream: .stdout) }
                }
            }
            stderrHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self else { return }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    Task { await self.ingest(data: data, stream: .stderr) }
                }
            }
            do {
                try process.run()
            } catch {
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                throw error
            }
        }

        func requestCancel() {
            guard !finished, process.isRunning else { return }
            cancelRequested = true
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            process.terminate()
            Task.detached { [weak self] in
                try? await Task.sleep(nanoseconds: SDKCodeBuildRunner.cancelGraceNanoseconds)
                guard let self else { return }
                let target = await self.killEscalationTarget()
                if let pid = target {
                    kill(pid, SIGKILL)
                }
            }
        }

        private func killEscalationTarget() -> pid_t? {
            guard cancelRequested, !finished, process.isRunning else { return nil }
            return process.processIdentifier
        }

        func waitForExit() async -> LocalProcessOutcome {
            while process.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            drain(stdoutHandle, stream: .stdout)
            drain(stderrHandle, stream: .stderr)
            flushRemainder(stream: .stdout)
            flushRemainder(stream: .stderr)
            finished = true
            try? stdoutHandle.close()
            try? stderrHandle.close()
            return LocalProcessOutcome(
                exitCode: process.terminationStatus,
                reason: process.terminationReason,
                cancelled: cancelRequested
            )
        }

        private func drain(_ handle: FileHandle, stream: SDKConsoleStream) {
            let data = handle.readDataToEndOfFile()
            if !data.isEmpty {
                ingest(data: data, stream: stream)
            }
        }

        private func ingest(data: Data, stream: SDKConsoleStream) {
            guard !finished else { return }
            let text = String(decoding: data, as: UTF8.self)
            guard !text.isEmpty else { return }
            switch stream {
            case .stdout:
                stdoutRemainder += text
                for line in takeCompleteLines(stream: .stdout) {
                    onLine(.stdout(line))
                }
            case .stderr:
                stderrRemainder += text
                for line in takeCompleteLines(stream: .stderr) {
                    onLine(.stderr(line))
                }
            case .system:
                break
            }
        }

        private func takeCompleteLines(stream: SDKConsoleStream) -> [String] {
            switch stream {
            case .stdout:
                var parts = stdoutRemainder.components(separatedBy: "\n")
                stdoutRemainder = parts.removeLast()
                return parts
            case .stderr:
                var parts = stderrRemainder.components(separatedBy: "\n")
                stderrRemainder = parts.removeLast()
                return parts
            case .system:
                return []
            }
        }

        private func flushRemainder(stream: SDKConsoleStream) {
            switch stream {
            case .stdout:
                if !stdoutRemainder.isEmpty {
                    onLine(.stdout(stdoutRemainder))
                    stdoutRemainder = ""
                }
            case .stderr:
                if !stderrRemainder.isEmpty {
                    onLine(.stderr(stderrRemainder))
                    stderrRemainder = ""
                }
            case .system:
                break
            }
        }
    }

    // MARK: - LocalProcessOutcome

    private struct LocalProcessOutcome: Sendable {
        let exitCode: Int32
        let reason: Process.TerminationReason
        let cancelled: Bool
    }
}
