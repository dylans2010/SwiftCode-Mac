// STAGED PORT — SwiftCode-Legacy `Backend/Assist/Assist Frameworks/AssistCodeIntegrityScanner.swift`
// (Legacy main d51a8f0d; Dylan's own code, direct port authorised under MIT).
// Target: SwiftCodeAssistant. Body is Legacy verbatim unless noted below.
// Dependency of _AssistCriticalAutonomousEngine (integrity-scan phase). Ledger SUPERSEDED by SwiftCodeMCP/SwiftCodeTools+StaticAnalysis.swift — same note as AssistFailureRootCauseAnalyzer: MCP tool surface, non-importable, no IntegrityReport class API. Ported verbatim.
// BLOCKED sub-dep: AssistVerificationPipeline.shared.verifySyntax(filePath:context:) (see AssistOutputVerificationEngine header). Placeholder/conflict-marker helpers reproduced below as file-private copies; delete if the pipeline is later ported.
// Remaining deps (now staged in AssistModels.swift by the parallel port — see _notes/agent-models-decisions.md): AssistContext (logger, fileSystem), AssistExecutionPlan/AssistExecutionStep/AssistExecutionStatus.

import Foundation

/// Scans generated code for integrity issues and potential problems
@MainActor
public final class AssistCodeIntegrityScanner {
    private let context: AssistContext

    public struct IntegrityReport {
        let hasIssues: Bool
        let syntaxErrors: [String]
        let structuralIssues: [String]
        let bestPracticeViolations: [String]
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Scans Swift code for integrity issues, including a real swiftc -parse pass.
    public func scanCode(at path: String) async -> IntegrityReport {
        await context.logger.info("Scanning code integrity: \(path)", toolId: "IntegrityScanner")

        guard let content = try? context.fileSystem.readFile(at: path) else {
            return IntegrityReport(
                hasIssues: true,
                syntaxErrors: ["Could not read file"],
                structuralIssues: [],
                bestPracticeViolations: []
            )
        }

        var syntaxErrors: [String] = []
        var structuralIssues: [String] = []
        var bestPracticeViolations: [String] = []

        // Check for basic Swift syntax patterns
        if content.contains("import") == false && path.hasSuffix(".swift") {
            bestPracticeViolations.append("Missing import statements")
        }

        // Check for unbalanced braces
        let openBraces = content.filter { $0 == "{" }.count
        let closeBraces = content.filter { $0 == "}" }.count
        if openBraces != closeBraces {
            syntaxErrors.append("Unbalanced braces: \(openBraces) open, \(closeBraces) close")
        }

        // Check for unbalanced parentheses
        let openParens = content.filter { $0 == "(" }.count
        let closeParens = content.filter { $0 == ")" }.count
        if openParens != closeParens {
            syntaxErrors.append("Unbalanced parentheses: \(openParens) open, \(closeParens) close")
        }

        // Check for incomplete implementations
        if content.contains("fatalError()") || content.contains("preconditionFailure()") {
            structuralIssues.append("Contains unimplemented code (fatalError/preconditionFailure)")
        }

        // Check for TODO/FIXME markers
        if content.contains("TODO") || content.contains("FIXME") {
            structuralIssues.append("Contains TODO/FIXME markers indicating incomplete work")
        }

        // Check for unresolved merge conflict markers
        if assistHasConflictMarkers(content) {
            syntaxErrors.append("Contains unresolved merge conflict markers")
        }

        // Check for empty bodies
        let emptyFunctionPattern = "(func|init)\\s+\\w+[^{]*\\{\\s*\\}"
        if content.range(of: emptyFunctionPattern, options: .regularExpression) != nil {
            structuralIssues.append("Contains empty function implementations")
        }

        // Real compiler-based syntax verification
        #if os(macOS)
        if path.hasSuffix(".swift") {
            let syntaxOutcome = await AssistVerificationPipeline.shared.verifySyntax(filePath: path, context: context)
            if !syntaxOutcome.isSuccess {
                syntaxErrors.append("swiftc -parse failed: \(syntaxOutcome.error ?? "syntax errors")")
            }
        }
        #endif

        let hasIssues = !syntaxErrors.isEmpty || !structuralIssues.isEmpty || !bestPracticeViolations.isEmpty

        return IntegrityReport(
            hasIssues: hasIssues,
            syntaxErrors: syntaxErrors,
            structuralIssues: structuralIssues,
            bestPracticeViolations: bestPracticeViolations
        )
    }

    /// Scans all files modified in a plan
    public func scanPlan(plan: AssistExecutionPlan) async -> [String: IntegrityReport] {
        var reports: [String: IntegrityReport] = [:]

        for step in plan.steps where ["file_write", "createFile", "generateFile"].contains(step.toolId) {
            if let path = step.input["path"], step.status == .completed {
                reports[path] = await scanCode(at: path)
            }
        }

        return reports
    }
}

// MARK: - Content checks (file-private copies of AssistVerificationPipeline helpers)
//
// Legacy defines these as `internal` funcs in Backend/Assist/AssistVerificationPipeline.swift.
// Reproduced here as file-private so this engine does not depend on the (not yet ported)
// verification pipeline. If that pipeline is later ported, delete these copies and use the
// shared helpers.
private func assistContainsPlaceholderToken(_ content: String) -> Bool {
    let tokens = [
        "TODO", "FIXME", "PLACEHOLDER", "STUB",
        "not implemented", "unimplemented",
        "fatalError(\"TODO", "fatalError(\"Stub", "fatalError(\"Not implemented", "fatalError(\"placeholder"
    ]
    return tokens.contains { content.contains($0) }
}

private func assistHasConflictMarkers(_ content: String) -> Bool {
    for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<<<<<<<") || trimmed.hasPrefix(">>>>>>>") || trimmed == "=======" {
            return true
        }
    }
    return false
}
