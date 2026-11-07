import Foundation

public enum AssistToolErrorCode: String, Codable, Sendable, CaseIterable {
    case missingArgument
    case invalidInput
    case notFound
    case permissionDenied
    case executionFailed
    case timeout
    case cancelled
    case resourceExhausted
    case unsupportedOperation
    case unknown

    public var recoveryHint: String {
        switch self {
        case .missingArgument:
            return "Re-run the tool with all required parameters filled in, following the tool's parameter schema."
        case .invalidInput:
            return "Fix the invalid parameter value (check ranges, types, and allowed values) and re-run the tool."
        case .notFound:
            return "Verify the path or identifier exists and re-run the tool with the corrected value."
        case .permissionDenied:
            return "Request the needed permission or choose a target inside the allowed workspace, then re-run."
        case .executionFailed:
            return "Inspect the diagnostics, fix the underlying cause, then re-run the tool."
        case .timeout:
            return "Re-run with a narrower scope or smaller input so it completes within the time limit."
        case .cancelled:
            return "Re-issue the request when you are ready for it to run to completion."
        case .resourceExhausted:
            return "Reduce the size or scope of the request and try again."
        case .unsupportedOperation:
            return "Choose a different tool or approach that supports this operation on the current platform."
        case .unknown:
            return "Re-run the tool; if the failure repeats, narrow the request and inspect the diagnostics."
        }
    }
}

public enum AssistToolResultFormatter {

    public static let maxOutputCharacters = 25_000
    public static let maxDiffCharacters = 8_000
    public static let maxStructuredValueCharacters = 8_000

    private static let contentKey = "content"
    private static let treeKey = "tree"
    private static let diffKey = "diff"

    public static func modelFacingPayload(toolId: String, result: AssistToolResult) -> String {
        var lines: [String] = []

        let status = result.success ? "SUCCESS" : "FAILURE"
        let durationText = String(format: "%.2fs", result.duration)
        lines.append("### \(toolId) — \(status) (\(durationText))")

        let data = result.data ?? [:]
        let primaryPayload = nonEmpty(data[contentKey]) ?? nonEmpty(data[treeKey])

        if let rangeLine = fileRangeMetadataLine(toolId: toolId, data: data) {
            lines.append(rangeLine)
        }

        lines.append("Output:")
        let outputText: String
        if let primaryPayload {
            outputText = primaryPayload
        } else if result.output.isEmpty {
            outputText = result.success ? "(empty)" : (result.error ?? "(empty)")
        } else {
            outputText = result.output
        }
        lines.append(capped(outputText, limit: maxOutputCharacters))

        let skippedKeys: Set<String> = [contentKey, treeKey, diffKey]
        let structuredKeys = data.keys.filter { !skippedKeys.contains($0) }.sorted()
        if !structuredKeys.isEmpty {
            lines.append("Structured data:")
            for key in structuredKeys {
                let value = capped(data[key] ?? "", limit: maxStructuredValueCharacters)
                lines.append("\(key)=\(value)")
            }
        }

        if !result.diagnostics.isEmpty {
            lines.append("Diagnostics:")
            for diagnostic in result.diagnostics {
                lines.append("- \(diagnostic)")
            }
        }

        if !result.filesChanged.isEmpty {
            lines.append("Files changed:")
            for file in result.filesChanged {
                lines.append("- \(file)")
            }
        }

        if let diff = result.diff, !diff.isEmpty {
            lines.append("Diff:")
            lines.append(capped(diff, limit: maxDiffCharacters))
        }

        if !result.success {
            let message = result.error ?? result.output
            if let code = result.toolErrorCode {
                lines.append("Error [\(code.rawValue)]: \(message)")
                lines.append("Recovery: \(code.recoveryHint)")
            } else {
                lines.append("Error: \(message)")
            }
            if !result.suggestedNextActions.isEmpty {
                lines.append("Suggested next: \(result.suggestedNextActions.joined(separator: ", "))")
            }
            if let exitCode = result.exitCode {
                lines.append("Exit code: \(exitCode)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func fileRangeMetadataLine(toolId: String, data: [String: String]) -> String? {
        var parts: [String] = []
        if let path = nonEmpty(data["path"]) {
            parts.append("path=\(path)")
        }
        let start = nonEmpty(data["start"]) ?? nonEmpty(data["startLine"])
        let end = nonEmpty(data["end"]) ?? nonEmpty(data["endLine"])
        if let start, let end {
            var range = "lines \(start)–\(end)"
            if let total = nonEmpty(data["totalLines"]) {
                range += " of \(total)"
            }
            parts.append(range)
        } else if let total = nonEmpty(data["totalLines"]) {
            parts.append("totalLines=\(total)")
        }
        if let fullyAvailable = nonEmpty(data["fullyAvailable"]) {
            parts.append("fullyAvailable=\(fullyAvailable)")
        }
        if let count = nonEmpty(data["count"]) ?? nonEmpty(data["entries"]) {
            parts.append("count=\(count)")
        }
        if let truncated = nonEmpty(data["truncated"]) {
            parts.append("truncated=\(truncated)")
        }
        guard !parts.isEmpty else { return nil }
        return "[\(toolId)] " + parts.joined(separator: ", ")
    }

    private static func capped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        return head + "\n[truncated: showing first \(limit) of \(text.count) characters — re-run with narrower arguments]"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
