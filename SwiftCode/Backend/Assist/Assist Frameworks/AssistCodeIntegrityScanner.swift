import Foundation

/// Scans generated code for integrity issues and potential problems
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

    /// Scans Swift code for integrity issues
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

        // Check for empty bodies
        let emptyFunctionPattern = "(func|init)\\s+\\w+[^{]*\\{\\s*\\}"
        if content.range(of: emptyFunctionPattern, options: .regularExpression) != nil {
            structuralIssues.append("Contains empty function implementations")
        }

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
