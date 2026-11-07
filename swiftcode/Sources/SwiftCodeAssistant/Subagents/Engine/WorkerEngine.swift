import Foundation
import SwiftCodeSubprocess
import os

public struct WorkerExecutionContext: Sendable {
    public var sessionId: UUID
    public var workspaceRoot: URL

    public init(sessionId: UUID = UUID(), workspaceRoot: URL) {
        self.sessionId = sessionId
        self.workspaceRoot = workspaceRoot
    }
}

public struct WorkerTurnOutput: Sendable {
    public var text: String
    public var activity: [String]
    public var filesChanged: [(path: String, changeType: FileChangeType)]

    public init(
        text: String = "",
        activity: [String] = [],
        filesChanged: [(path: String, changeType: FileChangeType)] = []
    ) {
        self.text = text
        self.activity = activity
        self.filesChanged = filesChanged
    }
}

@MainActor
public protocol WorkerTurnRunner: Sendable {
    func runTurn(
        prompt: String,
        history: [String],
        modelID: String,
        workspaceRoot: URL
    ) async throws -> WorkerTurnOutput
}

@MainActor
public struct MetaAssistTurnRunner: WorkerTurnRunner, Sendable {
    public var attachment: AgentAttachment?
    public var proxyBaseURL: String?
    public var reasoningEffort: String
    public var turnTimeoutSeconds: TimeInterval

    public init(
        attachment: AgentAttachment? = nil,
        proxyBaseURL: String? = nil,
        reasoningEffort: String = "high",
        turnTimeoutSeconds: TimeInterval = MetaAssistTurnExecutor.defaultTurnTimeout
    ) {
        self.attachment = attachment
        self.proxyBaseURL = proxyBaseURL
        self.reasoningEffort = reasoningEffort
        self.turnTimeoutSeconds = turnTimeoutSeconds
    }

    public func runTurn(
        prompt: String,
        history: [String],
        modelID: String,
        workspaceRoot: URL
    ) async throws -> WorkerTurnOutput {
        let provider = MetaAssistProvider(
            reasoningEffort: reasoningEffort,
            turnTimeoutSeconds: turnTimeoutSeconds,
            attachment: attachment,
            proxyBaseURL: proxyBaseURL
        )
        guard let executable = provider.executableURL() else {
            throw AssistantError.failed(MetaAssistProvider.notInstalledHint)
        }
        guard provider.hasCredentials() || provider.proxyBaseURL != nil else {
            throw AssistantError.notSignedIn(hint: MetaAssistProvider.notSignedInHint)
        }

        let before = WorkerWorkspaceSnapshot.capture(root: workspaceRoot)
        let collector = WorkerTurnEventCollector()
        try await MetaAssistTurnExecutor.shared.executeTurn(
            prompt: prompt,
            history: history.map { ChatMessage(.user, $0) },
            instructions: "",
            modelID: modelID.isEmpty ? MetaAssistProvider.defaultModelID : modelID,
            reasoningEffort: reasoningEffort,
            workspaceRoot: workspaceRoot.path,
            executable: executable,
            hasCredentials: provider.hasCredentials(),
            proxyBaseURL: provider.proxyBaseURL,
            attachment: provider.attachment,
            turnTimeoutSeconds: turnTimeoutSeconds,
            onEvent: { event in
                switch event {
                case .text(let delta): collector.appendText(delta)
                case .activity(let line): collector.appendActivity(line)
                case .truncated, .finished: break
                }
            }
        )
        let after = WorkerWorkspaceSnapshot.capture(root: workspaceRoot)
        return WorkerTurnOutput(
            text: collector.text,
            activity: collector.activity,
            filesChanged: before.changedPaths(comparedTo: after)
        )
    }
}

private final class WorkerTurnEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _text = ""
    private var _activity: [String] = []

    func appendText(_ delta: String) {
        lock.lock(); defer { lock.unlock() }
        _text += delta
    }

    func appendActivity(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        _activity.append(line)
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return _text
    }

    var activity: [String] {
        lock.lock(); defer { lock.unlock() }
        return _activity
    }
}

private struct WorkerWorkspaceSnapshot {
    private static let skippedDirectoryNames: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData", "node_modules", ".hg", ".svn",
    ]
    private static let maxFiles = 20_000

    private var files: [String: (mtime: TimeInterval, size: Int)]

    static func capture(root: URL) -> WorkerWorkspaceSnapshot {
        var files: [String: (mtime: TimeInterval, size: Int)] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return WorkerWorkspaceSnapshot(files: [:])
        }
        for case let url as URL in enumerator {
            if files.count >= maxFiles { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if skippedDirectoryNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            files[url.path] = (
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: values.fileSize ?? 0
            )
        }
        return WorkerWorkspaceSnapshot(files: files)
    }

    func changedPaths(comparedTo other: WorkerWorkspaceSnapshot) -> [(path: String, changeType: FileChangeType)] {
        var changes: [(path: String, changeType: FileChangeType)] = []
        for (path, after) in other.files {
            if let before = files[path] {
                if before != after { changes.append((path: path, changeType: .modified)) }
            } else {
                changes.append((path: path, changeType: .created))
            }
        }
        for path in files.keys where other.files[path] == nil {
            changes.append((path: path, changeType: .deleted))
        }
        return changes.sorted { $0.path < $1.path }
    }
}

private struct WorkerVerificationOutcome: Sendable {
    var isSuccess: Bool
    var error: String?
    var output: String
}

private struct WorkerBuildVerifier: Sendable {
    private let workspaceRoot: URL

    init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    func verifyCompilation() async -> WorkerVerificationOutcome {
        if FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("Package.swift").path) {
            return await runSwift(arguments: ["build"], successMarker: nil, kind: "swift build")
        }
        if let project = locateXcodeProject() {
            guard let scheme = await scheme(for: project) else {
                return WorkerVerificationOutcome(
                    isSuccess: false,
                    error: "No scheme found for \(project.lastPathComponent); cannot verify compilation.",
                    output: ""
                )
            }
            return await runXcodebuild(project: project, scheme: scheme, action: "build")
        }
        return WorkerVerificationOutcome(
            isSuccess: false,
            error: "No Xcode project (.xcodeproj/.xcworkspace) or Swift package found in the workspace; cannot verify compilation.",
            output: ""
        )
    }

    func verifyTests() async -> WorkerVerificationOutcome {
        if FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("Package.swift").path) {
            return await runSwift(arguments: ["test"], successMarker: nil, kind: "swift test")
        }
        if let project = locateXcodeProject() {
            guard let scheme = await scheme(for: project) else {
                return WorkerVerificationOutcome(
                    isSuccess: false,
                    error: "No scheme found for \(project.lastPathComponent); cannot verify tests.",
                    output: ""
                )
            }
            return await runXcodebuild(project: project, scheme: scheme, action: "test")
        }
        return WorkerVerificationOutcome(
            isSuccess: false,
            error: "No Xcode project (.xcodeproj/.xcworkspace) or Swift package found in the workspace; cannot verify tests.",
            output: ""
        )
    }

    private func locateXcodeProject() -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var workspace: URL?
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".git" || url.lastPathComponent == ".build" {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "xcworkspace" {
                return url
            }
            if url.pathExtension == "xcodeproj" && workspace == nil {
                workspace = url
            }
        }
        return workspace
    }

    private func scheme(for project: URL) async -> String? {
        let arg = project.pathExtension == "xcworkspace" ? "-workspace" : "-project"
        guard let output = try? await runProcess(
            executable: xcodebuildURL().path,
            arguments: [arg, project.path, "-list", "-json"]
        ) else { return nil }
        guard let data = output.stdoutText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let containerKey = project.pathExtension == "xcworkspace" ? "workspace" : "project"
        let container = json[containerKey] as? [String: Any]
        let schemes = container?["schemes"] as? [String]
        return schemes?.first
    }

    private func resolveDeveloperDir() -> String {
        for path in ["/Applications/Xcode.app/Contents/Developer", "/Applications/Xcode-beta.app/Contents/Developer"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return "/Applications/Xcode.app/Contents/Developer"
    }

    private func xcodebuildURL() -> URL {
        URL(fileURLWithPath: "\(resolveDeveloperDir())/usr/bin/xcodebuild")
    }

    private func runSwift(arguments: [String], successMarker: String?, kind: String) async -> WorkerVerificationOutcome {
        do {
            let output = try await runProcess(executable: "/usr/bin/swift", arguments: arguments)
            let combined = output.stdoutText + "\n" + output.stderrText
            let isSuccess = output.status == 0 && (successMarker == nil || combined.contains(successMarker!))
            return WorkerVerificationOutcome(
                isSuccess: isSuccess,
                error: isSuccess ? nil : "\(kind) exited with code \(output.status): \(output.stderrText.prefix(500))",
                output: output.stdoutText
            )
        } catch {
            return WorkerVerificationOutcome(isSuccess: false, error: error.localizedDescription, output: "")
        }
    }

    private func runXcodebuild(project: URL, scheme: String, action: String) async -> WorkerVerificationOutcome {
        let arg = project.pathExtension == "xcworkspace" ? "-workspace" : "-project"
        let arguments = [
            arg, project.path,
            "-scheme", scheme,
            "-destination", "platform=macOS,arch=arm64",
            action,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["DEVELOPER_DIR"] = resolveDeveloperDir()
        do {
            let output = try await runProcess(
                executable: xcodebuildURL().path,
                arguments: arguments,
                environment: environment
            )
            let combined = output.stdoutText + "\n" + output.stderrText
            let marker = action == "build" ? "** BUILD SUCCEEDED **" : "** TEST SUCCEEDED **"
            let isSuccess = output.status == 0 && combined.contains(marker)
            return WorkerVerificationOutcome(
                isSuccess: isSuccess,
                error: isSuccess ? nil : "xcodebuild \(action) did not report \(marker) (exit code \(output.status))",
                output: output.stdoutText
            )
        } catch {
            return WorkerVerificationOutcome(isSuccess: false, error: error.localizedDescription, output: "")
        }
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> Subprocess.Output {
        let root = workspaceRoot
        return try await Task.detached {
            try Subprocess.run(executable, arguments, environment: environment, currentDirectory: root)
        }.value
    }
}

@MainActor
public final class WorkerEngine: Sendable {
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerEngine")
    private let turnRunner: any WorkerTurnRunner

    public init(turnRunner: any WorkerTurnRunner = MetaAssistTurnRunner()) {
        self.turnRunner = turnRunner
    }

    public func execute(
        worker: Worker,
        scopedPrompt: String,
        context: WorkerExecutionContext,
        modelID: String
    ) async -> WorkerResult {
        let workerID = worker.id
        let workerName = worker.name

        transition(workerID: workerID, from: worker.status, to: .starting, reason: "Worker initialized and loading isolated context bundle...")
        transition(workerID: workerID, from: .starting, to: .working, reason: "Executing assigned task: \(worker.task)")

        var progress = WorkerProgress(
            narrative: "Executing implementation phase for scope '\(worker.scope)'",
            currentAction: "Inspecting codebase symbols and target files",
            phase: .implementation,
            nextPlan: "Perform required code mutations and file adjustments",
            percentage: 0.1
        )
        WorkerRuntimeState.shared.updateProgress(id: workerID, progress: progress)

        var completedWork: [String] = []
        var knownIssues: [String] = []
        var remainingWork: [String] = []
        var filesModifiedByWorker: [String] = []

        do {
            if Task.isCancelled || WorkerRuntimeState.shared.workers.first(where: { $0.id == workerID })?.status == .cancelled {
                return WorkerResult(
                    workerID: workerID,
                    workerName: workerName,
                    summary: "Worker was cancelled before completion.",
                    completedWork: completedWork,
                    knownIssues: ["Cancelled by user"],
                    remainingWork: [worker.task],
                    recommendedParentAction: "Review stopped state"
                )
            }

            logger.info("[Worker \(workerName)] Running turn with model '\(modelID)' for scope '\(worker.scope)'...")
            progress.currentAction = "Generating mutations for \(worker.scope)"
            progress.percentage = 0.2
            WorkerRuntimeState.shared.updateProgress(id: workerID, progress: progress)

            let fullPrompt = """
            \(scopedPrompt)

            # EXECUTION CONTRACT
            Complete your assigned task now, using the tools available to you.
            When the work is done, end your reply with a plain-language summary of what you changed, what you verified, and anything that remains unfinished.
            """

            var currentModel = modelID
            var turnOutput: WorkerTurnOutput?
            var turnError: Error?

            do {
                turnOutput = try await turnRunner.runTurn(
                    prompt: fullPrompt,
                    history: [],
                    modelID: currentModel,
                    workspaceRoot: context.workspaceRoot
                )
            } catch {
                turnError = error
                logger.warning("[Worker \(workerName)] Turn error: \(error.localizedDescription). Attempting recovery with a fallback model.")
                if let fallback = await WorkerModelSelector.shared.fallbackModel(for: currentModel) {
                    WorkerRuntimeState.shared.updateWorker(id: workerID) { w in
                        w.modelUsed = fallback
                    }
                    currentModel = fallback
                    turnOutput = try? await turnRunner.runTurn(
                        prompt: fullPrompt,
                        history: [],
                        modelID: fallback,
                        workspaceRoot: context.workspaceRoot
                    )
                }
            }

            let rawFinalResponse = turnOutput?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalResponse = (rawFinalResponse?.isEmpty == false) ? rawFinalResponse : nil
            if let finalResponse {
                completedWork.append(finalResponse)
            } else {
                if let turnError {
                    knownIssues.append("Turn failed: \(turnError.localizedDescription)")
                } else {
                    knownIssues.append("Turn returned no text.")
                }
                remainingWork.append(worker.task)
            }

            for (path, changeType) in turnOutput?.filesChanged ?? [] {
                WorkerRuntimeState.shared.recordFileChange(
                    id: workerID,
                    change: WorkerFileChange(path: path, changeType: changeType)
                )
                WorkerFileTracker.shared.registerOwnership(
                    workerID: workerID,
                    workerName: workerName,
                    filePath: path,
                    ownershipType: .exclusive
                )
                if !filesModifiedByWorker.contains(path) {
                    filesModifiedByWorker.append(path)
                }
            }
            progress.percentage = 0.7
            progress.currentAction = "Executed turn; \(filesModifiedByWorker.count) files changed"
            WorkerRuntimeState.shared.updateProgress(id: workerID, progress: progress)

            var buildResult = "Not executed"
            var testResults: [WorkerTestRecord] = []
            var verificationResult = finalResponse != nil ? "Tool execution completed" : "Incomplete"

            if !filesModifiedByWorker.isEmpty {
                progress.phase = .testing
                progress.currentAction = "Running build verification"
                progress.percentage = 0.75
                WorkerRuntimeState.shared.updateProgress(id: workerID, progress: progress)

                let verifier = WorkerBuildVerifier(workspaceRoot: context.workspaceRoot)
                let buildOutcome = await verifier.verifyCompilation()
                buildResult = buildOutcome.isSuccess ? "Passed" : "Failed"
                if !buildOutcome.isSuccess {
                    knownIssues.append("Build verification failed: \(buildOutcome.error ?? "unknown")")
                }

                progress.phase = .verification
                progress.currentAction = "Running test verification"
                progress.percentage = 0.85
                WorkerRuntimeState.shared.updateProgress(id: workerID, progress: progress)

                let testOutcome = await verifier.verifyTests()
                if testOutcome.isSuccess {
                    testResults = [WorkerTestRecord(testName: "Build & Test Verification", suite: "WorkerVerification", passed: true, output: "Tests passed")]
                    verificationResult = "Build and tests passed"
                } else {
                    knownIssues.append("Test verification failed: \(testOutcome.error ?? "unknown")")
                    verificationResult = "Build passed but tests failed"
                }
            }

            progress.phase = .verification
            progress.currentAction = "Verification complete"
            progress.percentage = 1.0
            WorkerRuntimeState.shared.updateProgress(id: workerID, progress: progress)

            let workerState = WorkerRuntimeState.shared.workers.first(where: { $0.id == workerID })
            let verificationState = finalResponse != nil ? "Completed" : "Incomplete"
            WorkerRuntimeState.shared.updateWorker(id: workerID) { w in
                w.verificationState = verificationState
                w.recap = completedWork
            }

            transition(workerID: workerID, from: .working, to: .reviewing, reason: "Implementation complete. Awaiting parent Assist review gate.")

            return WorkerResult(
                workerID: workerID,
                workerName: workerName,
                summary: finalResponse != nil
                    ? "Fulfilled scope '\(worker.scope)'. Task: \(worker.task)"
                    : "Incomplete scope '\(worker.scope)': the turn produced no final response.",
                completedWork: completedWork,
                modifiedFiles: workerState?.modifiedFiles.map { $0.path } ?? [],
                createdFiles: workerState?.createdFiles.map { $0.path } ?? [],
                deletedFiles: workerState?.deletedFiles.map { $0.path } ?? [],
                tests: testResults,
                buildResult: buildResult,
                verificationResult: verificationResult,
                knownIssues: knownIssues,
                remainingWork: remainingWork,
                recommendedParentAction: finalResponse != nil ? "Accept and integrate results" : "Re-execute or reassign remaining scope"
            )
        } catch {
            logger.error("[Worker \(workerName)] Failure during execution: \(error.localizedDescription)")
            let workerError = WorkerError(
                code: "EXECUTION_ERROR",
                message: error.localizedDescription,
                recoverable: true,
                rootCause: "Uncaught exception in Worker execution loop",
                remedy: "Engage WorkerRecoveryEngine or parent repair assignment"
            )

            WorkerRuntimeState.shared.updateWorker(id: workerID) { w in
                w.errorState = workerError
                w.status = .failed
                w.currentAction = "Failed: \(error.localizedDescription)"
            }

            transition(workerID: workerID, from: .working, to: .failed, reason: "Execution failure: \(error.localizedDescription)")

            return WorkerResult(
                workerID: workerID,
                workerName: workerName,
                summary: "Worker encountered failure: \(error.localizedDescription)",
                completedWork: completedWork,
                knownIssues: [error.localizedDescription],
                remainingWork: [worker.task],
                recommendedParentAction: "Repair or reassign remaining scope"
            )
        }
    }

    private func transition(workerID: UUID, from: WorkerStatus, to: WorkerStatus, reason: String) {
        guard from.canTransition(to: to) else {
            logger.warning("[Worker \(workerID)] Invalid transition: \(from.rawValue) -> \(to.rawValue)")
            return
        }
        WorkerRuntimeState.shared.transitionWorker(id: workerID, to: to, reason: reason)
        WorkerEventBus.shared.publish(WorkerEvent(
            workerID: workerID,
            type: .workerStarted,
            title: "Status Change",
            details: "\(from.rawValue) -> \(to.rawValue): \(reason)"
        ))
    }
}
