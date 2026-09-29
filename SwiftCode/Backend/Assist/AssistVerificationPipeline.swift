import Foundation
import os

// MARK: - Assist v3 Verification Pipeline

public struct VerificationOutcome: Sendable {
    public let kind: VerificationKind
    public let isSuccess: Bool
    public let diagnostics: [BuildDiagnostic]
    public let output: String
    public let error: String?
    public let duration: TimeInterval

    public init(
        kind: VerificationKind,
        isSuccess: Bool,
        diagnostics: [BuildDiagnostic] = [],
        output: String = "",
        error: String? = nil,
        duration: TimeInterval = 0
    ) {
        self.kind = kind
        self.isSuccess = isSuccess
        self.diagnostics = diagnostics
        self.output = output
        self.error = error
        self.duration = duration
    }
}

internal func assistContainsPlaceholderToken(_ content: String) -> Bool {
    let tokens = [
        "TODO", "FIXME", "PLACEHOLDER", "STUB",
        "not implemented", "unimplemented",
        "fatalError(\"TODO", "fatalError(\"Stub", "fatalError(\"Not implemented", "fatalError(\"placeholder"
    ]
    return tokens.contains { content.contains($0) }
}

internal func assistHasConflictMarkers(_ content: String) -> Bool {
    for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<<<<<<<") || trimmed.hasPrefix(">>>>>>>") || trimmed == "=======" {
            return true
        }
    }
    return false
}

internal func assistPathsMatch(_ expected: String, _ gitPath: String) -> Bool {
    let e = expected.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let g = gitPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return e == g || e.hasSuffix(g) || g.hasSuffix(e)
}

@MainActor
public final class AssistVerificationPipeline: Sendable {
    public static let shared = AssistVerificationPipeline()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistVerificationPipeline")

    private init() {}

    /// Discovers active Xcode DEVELOPER_DIR to ensure command reliability.
    public func resolveDeveloperDir() -> String {
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer",
            "/Applications/Xcode-beta.app/Contents/Developer"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "/Applications/Xcode.app/Contents/Developer"
    }

    /// Verifies individual Swift file syntax using swiftc typecheck pass.
    public func verifySyntax(filePath: String, context: AssistContext) async -> VerificationOutcome {
        let startTime = Date()
        let fullPath = context.workspaceRoot.appendingPathComponent(filePath).path

        guard FileManager.default.fileExists(atPath: fullPath) else {
            return VerificationOutcome(kind: .syntaxCheck, isSuccess: false, error: "File not found at \(filePath)", duration: 0)
        }

        #if os(macOS)
        let developerDir = resolveDeveloperDir()
        let swiftcURL = URL(fileURLWithPath: "\(developerDir)/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc")

        var env = ProcessInfo.processInfo.environment
        env["DEVELOPER_DIR"] = developerDir

        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: swiftcURL,
                arguments: ["-parse", fullPath],
                environment: env,
                workingDirectory: context.workspaceRoot
            )

            let duration = Date().timeIntervalSince(startTime)
            let combined = res.stdout + "\n" + res.stderr
            let diagnostics = parseDiagnostics(from: combined)

            let isSuccess = res.exitCode == 0 && diagnostics.filter { $0.severity == .error }.isEmpty
            return VerificationOutcome(
                kind: .syntaxCheck,
                isSuccess: isSuccess,
                diagnostics: diagnostics,
                output: res.stdout,
                error: isSuccess ? nil : res.stderr,
                duration: duration
            )
        } catch {
            return VerificationOutcome(kind: .syntaxCheck, isSuccess: false, error: error.localizedDescription, duration: Date().timeIntervalSince(startTime))
        }
        #else
        return VerificationOutcome(kind: .syntaxCheck, isSuccess: true, output: "Syntax check skipped on non-macOS target.", duration: 0)
        #endif
    }

    /// Verifies full project compilation using xcodebuild targeting macOS.
    public func verifyCompilation(context: AssistContext) async -> VerificationOutcome {
        let startTime = Date()
        let developerDir = resolveDeveloperDir()
        let xcodebuildURL = URL(fileURLWithPath: "\(developerDir)/usr/bin/xcodebuild")

        var env = ProcessInfo.processInfo.environment
        env["DEVELOPER_DIR"] = developerDir

        let projPath = context.workspaceRoot.appendingPathComponent("SwiftCode.xcodeproj").path

        guard FileManager.default.fileExists(atPath: projPath) else {
            return VerificationOutcome(kind: .compilation, isSuccess: true, output: "No Xcode project found; assuming standalone package.", duration: 0)
        }

        let arguments = [
            "-project", projPath,
            "-scheme", "SwiftCode",
            "-destination", "platform=macOS,arch=arm64",
            "build"
        ]

        logger.info("Executing compilation validation: xcodebuild \(arguments.joined(separator: " "))")

        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: xcodebuildURL,
                arguments: arguments,
                environment: env,
                workingDirectory: context.workspaceRoot
            )

            let duration = Date().timeIntervalSince(startTime)
            let combined = res.stdout + "\n" + res.stderr
            let diagnostics = parseDiagnostics(from: combined)
            let errors = diagnostics.filter { $0.severity == .error }

            let buildMarkerPresent = combined.contains("** BUILD SUCCEEDED **")
            let outputPresent = !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isSuccess = res.exitCode == 0 && buildMarkerPresent && errors.isEmpty && outputPresent

            return VerificationOutcome(
                kind: .compilation,
                isSuccess: isSuccess,
                diagnostics: diagnostics,
                output: res.stdout,
                error: isSuccess ? nil : (errors.first?.message ?? "xcodebuild did not report BUILD SUCCEEDED (exit code \(res.exitCode))"),
                duration: duration
            )
        } catch {
            return VerificationOutcome(kind: .compilation, isSuccess: false, error: error.localizedDescription, duration: Date().timeIntervalSince(startTime))
        }
    }

    /// Runs tests when a test scheme is available.
    public func verifyTests(context: AssistContext) async -> VerificationOutcome {
        let startTime = Date()
        let developerDir = resolveDeveloperDir()
        let xcodebuildURL = URL(fileURLWithPath: "\(developerDir)/usr/bin/xcodebuild")

        var env = ProcessInfo.processInfo.environment
        env["DEVELOPER_DIR"] = developerDir

        let projPath = context.workspaceRoot.appendingPathComponent("SwiftCode.xcodeproj").path

        guard FileManager.default.fileExists(atPath: projPath) else {
            return VerificationOutcome(
                kind: .unitTests,
                isSuccess: true,
                output: "No Xcode project present; test verification not applicable.",
                duration: 0
            )
        }

        let arguments = [
            "-project", projPath,
            "-scheme", "SwiftCode",
            "-destination", "platform=macOS,arch=arm64",
            "test"
        ]

        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: xcodebuildURL,
                arguments: arguments,
                environment: env,
                workingDirectory: context.workspaceRoot
            )

            let duration = Date().timeIntervalSince(startTime)
            let combined = res.stdout + "\n" + res.stderr
            let lower = combined.lowercased()

            let noTestTarget = lower.contains("not currently configured for the test action")
                || lower.contains("does not contain test targets")
                || lower.contains("no test targets")
                || lower.contains("no tests found")

            let failingTestLines = combined.components(separatedBy: .newlines).filter { $0.contains("' failed") }
            let testFailureMarkers = combined.contains("** TEST FAILED **")
                || lower.contains("testing failed")
                || !failingTestLines.isEmpty

            if testFailureMarkers || (res.exitCode != 0 && !noTestTarget) {
                let detail = failingTestLines.isEmpty
                    ? "xcodebuild test exited with code \(res.exitCode)"
                    : failingTestLines.prefix(5).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "; ")
                return VerificationOutcome(
                    kind: .unitTests,
                    isSuccess: false,
                    output: res.stdout,
                    error: "Test execution failed: \(detail)",
                    duration: duration
                )
            }

            if noTestTarget {
                return VerificationOutcome(
                    kind: .unitTests,
                    isSuccess: true,
                    output: "Scheme has no test targets configured; nothing to run.\n\(res.stdout)",
                    duration: duration
                )
            }

            let isSuccess = res.exitCode == 0
            return VerificationOutcome(
                kind: .unitTests,
                isSuccess: isSuccess,
                output: res.stdout,
                error: isSuccess ? nil : "Test run exited with code \(res.exitCode)",
                duration: duration
            )
        } catch {
            return VerificationOutcome(
                kind: .unitTests,
                isSuccess: false,
                error: "Test runner could not be executed: \(error.localizedDescription)",
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Audits Git diff for forbidden placeholders, verifies expected files exist with real
    /// content, and flags changes to files outside the declared task scope.
    public func verifyDiffCompleteness(context: AssistContext, expectedFiles: [String]) async -> VerificationOutcome {
        let startTime = Date()
        var issues: [String] = []

        var gitAvailable = false
        do {
            let status = try await GitService.shared.getStatus(for: context.workspaceRoot)
            gitAvailable = true

            let diffHunks = try await GitService.shared.getDiff(repositoryURL: context.workspaceRoot)
            for hunk in diffHunks {
                for line in hunk.lines where line.hasPrefix("+") {
                    let content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if assistContainsPlaceholderToken(content) {
                        issues.append("Incomplete placeholder in diff: '\(content)'")
                    }
                }
            }

            for file in status.files {
                let gitPath = file.path.path
                if !expectedFiles.contains(where: { assistPathsMatch($0, gitPath) }) {
                    issues.append("Unexpected change to '\(gitPath)' (status: \(file.status.rawValue)) — not declared in task file list")
                }
            }
        } catch {
            logger.info("Git diff audit unavailable (\(error.localizedDescription)); falling back to direct file content scan")
        }

        for expected in expectedFiles {
            if !context.fileSystem.exists(at: expected) {
                issues.append("Expected file '\(expected)' does not exist on disk")
                continue
            }
            if let content = try? context.fileSystem.readFile(at: expected) {
                if assistHasConflictMarkers(content) {
                    issues.append("File '\(expected)' contains unresolved merge conflict markers")
                }
                if assistContainsPlaceholderToken(content) {
                    issues.append("File '\(expected)' contains placeholder tokens (TODO/FIXME/STUB)")
                }
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("File '\(expected)' is empty")
                }
            }
        }

        let isSuccess = issues.isEmpty
        return VerificationOutcome(
            kind: .diffAudit,
            isSuccess: isSuccess,
            output: isSuccess
                ? "Diff audit passed: \(expectedFiles.count) expected file(s) verified, no placeholders, no unexpected changes."
                : "",
            error: isSuccess ? nil : issues.joined(separator: "; "),
            duration: Date().timeIntervalSince(startTime)
        )
    }

    public struct CompletionContractReport: Sendable {
        public let passed: Bool
        public let issues: [String]
        public let unsatisfiedRequirements: [String]

        public init(passed: Bool, issues: [String] = [], unsatisfiedRequirements: [String] = []) {
            self.passed = passed
            self.issues = issues
            self.unsatisfiedRequirements = unsatisfiedRequirements
        }
    }

    /// Evaluates the 7 mandatory completion criteria against reality.
    @discardableResult
    public func evaluateCompletionContract(
        task: inout AgentTask,
        context: AssistContext,
        didBuildSucceed: Bool,
        didTestsSucceed: Bool,
        diffAuditPassed: Bool
    ) -> Bool {
        let isReadOnly = task.filesInvolved.isEmpty && task.completedOperations.isEmpty

        for i in 0..<task.completionCriteria.count {
            let criterion = task.completionCriteria[i]
            switch criterion.type {
            case .requestUnderstood:
                task.completionCriteria[i].isMet = !task.interpretedObjective.isEmpty
                task.completionCriteria[i].evidence = "Objective understood: \(task.interpretedObjective)"
            case .implementationComplete:
                if isReadOnly {
                    task.completionCriteria[i].isMet = true
                    task.completionCriteria[i].evidence = "Read-only analysis / assessment complete."
                } else {
                    let incomplete = task.completedOperations.filter { $0.status != .completed }
                    task.completionCriteria[i].isMet = !task.completedOperations.isEmpty && incomplete.isEmpty
                    task.completionCriteria[i].evidence = "\(task.completedOperations.count) operations landed, \(incomplete.isEmpty ? "all completed" : "\(incomplete.count) incomplete")."
                }
            case .expectedFilesChanged:
                if isReadOnly {
                    task.completionCriteria[i].isMet = true
                    task.completionCriteria[i].evidence = "Read-only task; no file modifications expected."
                } else {
                    let missing = task.filesInvolved.filter { !context.fileSystem.exists(at: $0) }
                    task.completionCriteria[i].isMet = !task.filesInvolved.isEmpty && missing.isEmpty
                    task.completionCriteria[i].evidence = missing.isEmpty
                        ? "All \(task.filesInvolved.count) involved files exist on disk."
                        : "Missing files: \(missing.joined(separator: ", "))"
                }
            case .buildVerified:
                if isReadOnly {
                    task.completionCriteria[i].isMet = true
                    task.completionCriteria[i].evidence = "Read-only task; build verification bypassed."
                } else {
                    task.completionCriteria[i].isMet = didBuildSucceed
                    task.completionCriteria[i].evidence = didBuildSucceed ? "Build verified clean via xcodebuild." : "Build failed or not run."
                }
            case .testsVerified:
                task.completionCriteria[i].isMet = didTestsSucceed
                task.completionCriteria[i].evidence = didTestsSucceed ? "Tests verified clean." : "Tests failed."
            case .diffReviewed:
                if isReadOnly {
                    task.completionCriteria[i].isMet = true
                    task.completionCriteria[i].evidence = "Read-only task; no diffs to review."
                } else {
                    task.completionCriteria[i].isMet = diffAuditPassed
                    task.completionCriteria[i].evidence = diffAuditPassed ? "Diff contains no placeholders and no unexpected changes." : "Diff audit failed."
                }
            case .noBlockingErrors:
                let clear = task.unresolvedIssues.isEmpty && didBuildSucceed && didTestsSucceed && diffAuditPassed
                task.completionCriteria[i].isMet = clear
                task.completionCriteria[i].evidence = clear
                    ? "No active blocking errors."
                    : "Unresolved: \(task.unresolvedIssues.joined(separator: ", ")); build=\(didBuildSucceed), tests=\(didTestsSucceed), diff=\(diffAuditPassed)"
            }
        }

        return task.completionCriteria.allSatisfy { $0.isMet }
    }

    /// Evaluates the 7 mandatory completion criteria against reality asynchronously, executing real
    /// build, test, diff, and per-file syntax checks. Completion is only reported when objective
    /// evidence supports it — never on model claims alone.
    public func evaluateCompletionContract(
        task: inout AgentTask,
        context: AssistContext
    ) async -> CompletionContractReport {
        let isReadOnly = task.filesInvolved.isEmpty && task.completedOperations.isEmpty
        if isReadOnly {
            _ = evaluateCompletionContract(
                task: &task,
                context: context,
                didBuildSucceed: true,
                didTestsSucceed: true,
                diffAuditPassed: true
            )
            return CompletionContractReport(passed: true, issues: [], unsatisfiedRequirements: [])
        }

        let testOutcome = await verifyTests(context: context)

        // xcodebuild test compiles before testing, so a passing test run implies a successful build.
        let buildOutcome: VerificationOutcome
        if testOutcome.isSuccess {
            buildOutcome = VerificationOutcome(
                kind: .compilation,
                isSuccess: true,
                output: "Build implied successful by passing test run.",
                duration: testOutcome.duration
            )
        } else {
            buildOutcome = await verifyCompilation(context: context)
        }

        let diffOutcome = await verifyDiffCompleteness(context: context, expectedFiles: task.filesInvolved)

        var fileIssues: [String] = []
        for file in task.filesInvolved {
            if !context.fileSystem.exists(at: file) {
                fileIssues.append("Involved file '\(file)' is missing from disk")
                continue
            }
            let syntaxOutcome = await verifySyntax(filePath: file, context: context)
            if !syntaxOutcome.isSuccess {
                fileIssues.append("Syntax verification failed for '\(file)': \(syntaxOutcome.error ?? "parse errors")")
            }
        }

        let didBuildSucceed = buildOutcome.isSuccess
        let didTestsSucceed = testOutcome.isSuccess
        let diffAuditPassed = diffOutcome.isSuccess

        _ = evaluateCompletionContract(
            task: &task,
            context: context,
            didBuildSucceed: didBuildSucceed,
            didTestsSucceed: didTestsSucceed,
            diffAuditPassed: diffAuditPassed
        )

        var issues: [String] = []
        if !didBuildSucceed {
            issues.append(buildOutcome.error ?? "Compilation build failed.")
        }
        if !didTestsSucceed {
            issues.append(testOutcome.error ?? "Test verification failed.")
        }
        if !diffAuditPassed {
            issues.append(diffOutcome.error ?? "Diff audit failed.")
        }
        issues.append(contentsOf: fileIssues)

        for i in 0..<task.verificationRequirements.count {
            let requirement = task.verificationRequirements[i]
            let outcome: VerificationOutcome
            switch requirement.kind {
            case .syntaxCheck:
                if let first = task.filesInvolved.first {
                    outcome = await verifySyntax(filePath: first, context: context)
                } else {
                    outcome = VerificationOutcome(kind: .syntaxCheck, isSuccess: true, output: "No files to syntax-check.")
                }
            case .compilation:
                outcome = buildOutcome
            case .unitTests:
                outcome = testOutcome
            case .diffAudit:
                outcome = diffOutcome
            case .custom:
                if diffOutcome.isSuccess && fileIssues.isEmpty {
                    outcome = VerificationOutcome(kind: .custom, isSuccess: true, output: "Custom requirement satisfied by diff and file checks.")
                } else {
                    outcome = VerificationOutcome(kind: .custom, isSuccess: false, error: "Custom requirement not satisfied: \(fileIssues.joined(separator: "; "))")
                }
            }

            task.verificationRequirements[i].isSatisfied = outcome.isSuccess
            task.verificationRequirements[i].evidence = outcome.isSuccess
                ? "Objectively verified: \(String(outcome.output.prefix(300)))"
                : "Verification failed: \(outcome.error ?? "check did not pass")"
            task.verificationRequirements[i].evaluatedAt = Date()
        }

        let unsatisfied = task.completionCriteria.filter { !$0.isMet }.map { "\($0.type.rawValue): \($0.evidence)" }
        let unsatisfiedRequirements = task.verificationRequirements.filter { !$0.isSatisfied }.map { "\($0.kind.rawValue): \($0.description)" }

        let allMet = task.completionCriteria.allSatisfy { $0.isMet }
            && task.verificationRequirements.allSatisfy { $0.isSatisfied }
            && issues.isEmpty

        return CompletionContractReport(passed: allMet, issues: issues, unsatisfiedRequirements: unsatisfied + unsatisfiedRequirements)
    }

    private func parseDiagnostics(from log: String) -> [BuildDiagnostic] {
        var results: [BuildDiagnostic] = []
        let lines = log.components(separatedBy: .newlines)
        for line in lines {
            if let diag = BuildLogLineParser.shared.parse(line) {
                results.append(diag)
            }
        }
        return results
    }
}
