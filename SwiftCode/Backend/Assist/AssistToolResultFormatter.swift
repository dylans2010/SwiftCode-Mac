import Foundation

// MARK: - Assist Tool Error Codes

/// Machine-readable error taxonomy for Assist tool failures.
///
/// Every tool failure carries one of these codes (via `AssistToolResult.toolErrorCode`)
/// so models can branch on the failure kind instead of parsing message text.
/// `recoveryHint` gives the model one actionable sentence for getting unstuck.
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

    /// One actionable sentence telling the model how to recover from this failure.
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

// MARK: - Canonical Model-Facing Tool Result Serializer

/// The single canonical serializer for sending Assist tool results to AI models.
///
/// Every model-boundary serializer (Gemini runtime, other-models bridge, worker
/// engine, transport) routes through `modelFacingPayload(toolId:result:)` so models
/// always see the same sections, caps, truncation markers, and error taxonomy —
/// in particular the file-range metadata (path/start/end/totalLines/...) that
/// ad-hoc flattening used to drop on the Gemini path.
public enum AssistToolResultFormatter {

    /// Hard cap for the Output section, in characters.
    public static let maxOutputCharacters = 25_000
    /// Hard cap for the Diff section, in characters.
    public static let maxDiffCharacters = 8_000
    /// Hard cap for a single Structured data value, in characters.
    public static let maxStructuredValueCharacters = 8_000

    // Data-dict keys. String literals (not AssistToolDataKey statics) so this
    // file compiles unchanged whether AssistToolDataKey keeps its static-let
    // shape or migrates to String raw-value cases; the values are identical.
    private static let contentKey = "content"
    private static let treeKey = "tree"
    private static let diffKey = "diff"

    /// Builds the canonical model-facing payload for one tool execution.
    ///
    /// Layout:
    /// ```
    /// ### <toolId> — SUCCESS|FAILURE (<duration>s)
    /// [<toolId>] path=… lines 240–280 of 5432, fullyAvailable=false   (when range metadata applies)
    /// Output:
    /// <output, capped at 25,000 chars with an exact truncation marker>
    /// Structured data:
    /// key=value ...
    /// Diagnostics:
    /// - ...
    /// Files changed:
    /// - ...
    /// Diff:
    /// <diff, capped at 8,000 chars>
    /// Error [<code>]: <message>        (failures only)
    /// Recovery: <hint>
    /// Suggested next: a, b
    /// Exit code: <n>
    /// ```
    public static func modelFacingPayload(toolId: String, result: AssistToolResult) -> String {
        var lines: [String] = []

        // Header.
        let status = result.success ? "SUCCESS" : "FAILURE"
        let durationText = String(format: "%.2fs", result.duration)
        lines.append("### \(toolId) — \(status) (\(durationText))")

        let data = result.data ?? [:]
        let primaryPayload = nonEmpty(data[contentKey]) ?? nonEmpty(data[treeKey])

        // File-range metadata line: emitted when data carries keys beyond the
        // content/tree payload (path, line ranges, counts, ...). This is the
        // metadata the Gemini flattening path used to drop.
        if let rangeLine = fileRangeMetadataLine(toolId: toolId, data: data) {
            lines.append(rangeLine)
        }

        // Output section: the primary payload (file content / tree) when one
        // was provided, otherwise the tool's own output text.
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

        // Structured data: every data key except the payload keys already
        // shown above (and the diff, which has its own section).
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

        // Failure footer: machine-readable code, recovery hint, suggestions.
        if !result.success {
            let message = result.error ?? result.output
            // NOTE: `toolErrorCode` is added to AssistToolResult by the
            // error-code migration (Area 2) in the same module; this reference
            // resolves once that lands.
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

    // MARK: - Private helpers

    /// One compact metadata line from file-range keys, e.g.
    /// `[file_read] path=/x/y.swift, lines 240–280 of 5432, fullyAvailable=false`.
    /// Returns nil when no range keys are present (i.e. data holds nothing
    /// beyond the content/tree payload).
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

    /// Caps text at `limit` characters, marking truncation with the exact
    /// canonical marker so a model never mistakes a cut payload for a whole one.
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
