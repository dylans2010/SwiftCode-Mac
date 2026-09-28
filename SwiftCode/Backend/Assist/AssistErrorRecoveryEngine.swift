import Foundation
import os

// MARK: - Recovery Domains & Scoped Recovery Budgets

public enum RecoveryDomain: String, Codable, Sendable, CaseIterable {
    case tool = "Tool Recovery"
    case model = "Model Recovery"
    case build = "Build Recovery"
    case test = "Test Recovery"
    case worker = "Worker Recovery"
    case network = "Network Recovery"
    case file = "File Recovery"
    case context = "Context Recovery"
}

public struct ToolValidationResult: @unchecked Sendable {
    public let isValid: Bool
    public let issue: String?
    public let correctedInput: [String: Any]?

    public init(isValid: Bool, issue: String? = nil, correctedInput: [String: Any]? = nil) {
        self.isValid = isValid
        self.issue = issue
        self.correctedInput = correctedInput
    }
}

// MARK: - Assist Autonomous Error Recovery Engine

@MainActor
public final class AssistErrorRecoveryEngine: Sendable {
    public static let shared = AssistErrorRecoveryEngine()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistErrorRecoveryEngine")

    // Domain-scoped recovery attempt counters capped strictly at 5 (never 6/5)
    private var domainCounters: [RecoveryDomain: Int] = [:]
    private var activeSessionFailures: [TaskFailure] = []
    private var signatureCounts: [String: Int] = [:]
    private var previousToolCalls: [String: String] = [:] // Signature to output hash

    private init() {
        resetSession()
    }

    public func resetSession() {
        domainCounters.removeAll()
        for domain in RecoveryDomain.allCases {
            domainCounters[domain] = 0
        }
        activeSessionFailures.removeAll()
        signatureCounts.removeAll()
        previousToolCalls.removeAll()
    }

    /// Checks if recovery is allowed under the domain budget without exceeding 5 attempts.
    public func canAttemptRecovery(domain: RecoveryDomain, maxAllowed: Int = 5) -> Bool {
        let current = domainCounters[domain, default: 0]
        return current < maxAllowed
    }

    /// Increments and returns the bounded attempt number guaranteed to never exceed maxAllowed (e.g. 1/5 .. 5/5).
    public func recordRecoveryAttempt(domain: RecoveryDomain, maxAllowed: Int = 5) -> (attemptNumber: Int, maxAllowed: Int, allowed: Bool) {
        let current = domainCounters[domain, default: 0]
        if current >= maxAllowed {
            logger.warning("Recovery budget exhausted for domain \(domain.rawValue): \(current)/\(maxAllowed)")
            return (maxAllowed, maxAllowed, false)
        }

        let next = min(current + 1, maxAllowed)
        domainCounters[domain] = next
        logger.info("Recorded recovery attempt for \(domain.rawValue): \(next)/\(maxAllowed)")
        return (next, maxAllowed, true)
    }

    /// Pre-execution tool validation to prevent schema errors from consuming generic task repair budget.
    public func validateToolCall(
        toolId: String,
        input: [String: Any],
        registry: AssistToolRegistry
    ) -> ToolValidationResult {
        // 1. Tool availability
        guard registry.getTool(toolId) != nil else {
            return ToolValidationResult(isValid: false, issue: "Tool '\(toolId)' is not registered or available in current environment.")
        }

        var mutableInput = input

        // 2. Validate path requirements if tool expects a path
        let pathKeys = ["path", "filepath", "target", "filePath", "source", "destination"]
        for key in pathKeys {
            if let pathVal = mutableInput[key] as? String {
                let trimmed = pathVal.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("/") || trimmed.contains("..") {
                    // Pre-correct invalid path traversal or absolute root path
                    let cleaned = trimmed.replacingOccurrences(of: "../", with: "")
                                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    mutableInput[key] = cleaned
                    logger.info("Auto-corrected parameter '\(key)' from '\(pathVal)' to '\(cleaned)'")
                    return ToolValidationResult(
                        isValid: true,
                        issue: "Auto-corrected relative path",
                        correctedInput: mutableInput
                    )
                }
            }
        }

        // 3. Tool specific schema checks
        if toolId == "file_write" || toolId == "file_create" {
            if mutableInput["path"] == nil && mutableInput["filepath"] != nil {
                mutableInput["path"] = mutableInput["filepath"]
            }
            if mutableInput["path"] == nil {
                return ToolValidationResult(isValid: false, issue: "Missing required parameter 'path' for tool \(toolId)")
            }
        }

        if toolId == "code_replace" || toolId == "replace_in_file" {
            if mutableInput["targetText"] == nil && mutableInput["target_text"] != nil {
                mutableInput["targetText"] = mutableInput["target_text"]
            }
            if mutableInput["replacementText"] == nil && mutableInput["replacement_text"] != nil {
                mutableInput["replacementText"] = mutableInput["replacement_text"]
            }
        }

        return ToolValidationResult(isValid: true, issue: nil, correctedInput: mutableInput)
    }

    /// Detects if an exact duplicate tool call with identical arguments failed previously.
    public func isIdenticalFailure(toolId: String, input: [String: Any], error: String) -> Bool {
        let callSignature = "\(toolId)::\(input.description)"
        if let prevError = previousToolCalls[callSignature], prevError == error {
            return true
        }
        previousToolCalls[callSignature] = error
        return false
    }

    /// Classifies an error message into a structured FailureCategory.
    public func classify(message: String, exitCode: Int? = nil) -> FailureCategory {
        let lower = message.lowercased()

        if lower.contains("error:") || lower.contains("cannot find") || lower.contains("type mismatch") || lower.contains("unresolved identifier") {
            return .compilerError
        }
        if lower.contains("test failed") || lower.contains("xctest") || lower.contains("assertion failed") {
            return .testFailure
        }
        if lower.contains("target text") || lower.contains("conflict") || lower.contains("not found in") || lower.contains("multiple matches") {
            return .editConflict
        }
        if lower.contains("sandbox") || lower.contains("traversal") || lower.contains("permission denied") || lower.contains("security") {
            return .sandboxViolation
        }
        if lower.contains("stagnation") || lower.contains("infinite loop") || lower.contains("oscillation") {
            return .loopStagnation
        }
        if lower.contains("ambiguity") || lower.contains("underspecified") {
            return .ambiguity
        }
        if exitCode != 0 && exitCode != nil {
            return .toolError
        }
        return .unknown
    }

    /// Computes a normalized error signature to detect repetitions and thrashing.
    public func computeSignature(category: FailureCategory, message: String) -> String {
        let cleaned = message
            .replacingOccurrences(of: "0x[0-9a-fA-F]+", with: "ADDR", options: .regularExpression)
            .replacingOccurrences(of: ":\\d+:\\d+:", with: ":LINE:COL:", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix = String(cleaned.prefix(120))
        return "\(category.rawValue)::\(prefix)"
    }

    /// Records a failure in the task failure memory and checks for thrashing.
    public func recordFailure(
        task: inout AgentTask,
        message: String,
        iteration: Int,
        exitCode: Int? = nil
    ) -> (failure: TaskFailure, isThrashing: Bool) {
        let category = classify(message: message, exitCode: exitCode)
        let signature = computeSignature(category: category, message: message)

        let failure = TaskFailure(
            iteration: iteration,
            signature: signature,
            category: category,
            message: message
        )
        task.failures.append(failure)

        let signatureCount = task.failures.filter { $0.signature == signature }.count
        let isThrashing = signatureCount >= task.budgets.maxRepeatedFailures

        if isThrashing {
            logger.error("Thrashing detected! Same failure signature repeated \(signatureCount) times: \(signature)")
        }

        return (failure, isThrashing)
    }

    /// Formulates an actionable, targeted repair hypothesis.
    public func formulateRepairHypothesis(failure: TaskFailure, task: AgentTask) -> RepairAttempt {
        let msg = failure.message
        var hypothesis = ""
        var strategy = ""

        switch failure.category {
        case .compilerError:
            if msg.contains("cannot find") || msg.contains("in scope") {
                hypothesis = "A referenced symbol or type is missing or its enclosing module is not imported."
                strategy = "Inspect imports and search codebase for the symbol definition, then add the appropriate import or definition."
            } else if msg.contains("type mismatch") || msg.contains("cannot convert value of type") {
                hypothesis = "A type mismatch occurred between expected parameter and provided value."
                strategy = "Read the method signature and cast or convert the type to match the expected parameter."
            } else if msg.contains("has no member") {
                hypothesis = "Accessing a non-existent property or method on a model or class."
                strategy = "Read the type declaration to identify available properties or methods, and update call site."
            } else {
                hypothesis = "A compiler syntax or type-check error occurred."
                strategy = "Isolate the failing line from the compiler diagnostic, re-read the file, and apply a targeted replacement."
            }

        case .editConflict:
            hypothesis = "Target text in the file does not match what was expected, likely due to a previous modification."
            strategy = "Re-read the target file at its current line offset, extract the exact target text, and re-apply a targeted patch."

        case .testFailure:
            hypothesis = "One or more tests failed, indicating a behavior regression or invalid assertion."
            strategy = "Inspect the test failure assertion, verify requirements, and adjust implementation."

        case .sandboxViolation:
            hypothesis = "A tool attempted to access paths outside the project workspace."
            strategy = "Restrict all file paths to relative project paths within workspaceRoot."

        case .loopStagnation:
            hypothesis = "The agent loop is stagnating or repeating similar actions without disk changes."
            strategy = "Pivot to an alternative implementation strategy or consult the user."

        default:
            hypothesis = "An unexpected error occurred during execution."
            strategy = "Inspect the failure output, re-evaluate assumptions, and retry with smaller scoped action."
        }

        return RepairAttempt(
            failureSignature: failure.signature,
            hypothesis: hypothesis,
            strategy: strategy
        )
    }

    @discardableResult
    public func recordFailure(toolId: String, error: String, context: String = "") -> TaskFailure {
        let category = classify(message: error)
        let signature = computeSignature(category: category, message: "\(toolId)::\(error)")
        let failure = TaskFailure(
            iteration: activeSessionFailures.count + 1,
            signature: signature,
            category: category,
            message: error
        )
        activeSessionFailures.append(failure)
        signatureCounts[signature, default: 0] += 1
        return failure
    }

    public func detectThrashing(threshold: Int = 3) -> String? {
        for (sig, count) in signatureCounts where count >= threshold {
            return "Repeated identical failure occurred \(count) times: '\(sig)'"
        }
        return nil
    }

    public func generateRepairHypothesis(for failure: TaskFailure) -> String {
        let dummyTask = AgentTask(objective: "")
        let repair = formulateRepairHypothesis(failure: failure, task: dummyTask)
        return "\(repair.hypothesis) Strategy: \(repair.strategy)"
    }

    public func formatFailuresForPrompt() -> String {
        guard !activeSessionFailures.isEmpty else { return "" }
        var result = ""
        for failure in activeSessionFailures.suffix(3) {
            result += "- Failure: [\(failure.category.rawValue)] \(failure.message.prefix(120))\n"
        }
        return result
    }
}
