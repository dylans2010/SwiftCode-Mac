//
//  ReportToUserTool.swift
//  SwiftCode
//
//  Production Assist tool invoked upon task completion to report verified outcomes to the user.
//  Responsible for stripping broken markdown artifacts, normalizing presentation, and rendering
//  clean, executive-level summaries without leaking raw tool tokens or JSON schemas.
//

import Foundation
import os

@MainActor
public struct ReportToUserTool: AssistTool {
    public let id: String = "report_to_user"
    public let name: String = "Report Task Completion to User"
    public let description: String = """
    Delivers the authoritative task completion report to the user once all task work, \
    builds, tests, and audits are fully finished. Must be called at all times when Assist \
    finishes doing task work. Not for conversational Q&A. Cleans and renders polished Markdown.
    """

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Presents the final task completion summary to the user with clean markdown formatting.",
            properties: [
                "summary": JSONSchema(
                    type: "string",
                    description: "Structured, concise completion report summarizing work done, files modified, and build/test verification results. Clean Markdown formatted."
                ),
                "status": JSONSchema(
                    type: "string",
                    description: "Task outcome status (e.g. 'completed', 'verified', 'partially_completed')."
                ),
                "filesModified": JSONSchema(
                    type: "array",
                    description: "List of files that were created, updated, or audited during this task execution.",
                    items: JSONSchema(type: "string", description: "Relative file path")
                ),
                "verification": JSONSchema(
                    type: "string",
                    description: "Build, compiler diagnostic, and automated test execution results proving correctness."
                )
            ],
            required: ["summary"]
        )
    }

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .safeRead }
    public var isReadOnly: Bool { true }
    public var isMutating: Bool { false }
    public var estimatedCost: Double { 0.0 }

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "ReportToUserTool")

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        logger.info("Executing report_to_user tool...")

        let rawSummary = (input["summary"] as? String)
            ?? (input["message"] as? String)
            ?? (input["report"] as? String)
            ?? (input["text"] as? String)
            ?? "Task execution completed."

        let status = (input["status"] as? String) ?? "completed"
        let files = (input["filesModified"] as? [String]) ?? []
        let verification = (input["verification"] as? String) ?? ""

        // Process markdown: strip unrendered glitches, tool JSON noise, and normalize prose
        let renderedSummary = Self.normalizeAndRenderMarkdown(rawSummary)

        // Broadcast to AssistManager to update final response view if needed
        var finalContent = renderedSummary
        if !files.isEmpty && !finalContent.contains(files.first ?? "") {
            finalContent += "\n\n**Modified Files:**\n" + files.map { "- `\($0)`" }.joined(separator: "\n")
        }
        if !verification.isEmpty && !finalContent.contains(verification) {
            finalContent += "\n\n**Verification:**\n\(verification)"
        }

        // Post completion to AssistManager
        AssistManager.shared.updateLastAssistantMessageContent(finalContent)

        return .success(
            finalContent,
            data: [
                "status": status,
                "filesCount": "\(files.count)",
                "renderedLength": "\(finalContent.count)"
            ]
        )
    }

    /// Normalizes and cleans raw markdown syntax, stripping broken escapes, raw schemas, or ASCII tables.
    public static func normalizeAndRenderMarkdown(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip raw JSON tool wrappers if mistakenly dumped
        if text.hasPrefix("```json") && text.hasSuffix("```") {
            let inner = text.dropFirst(7).dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = inner.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let summary = json["summary"] as? String {
                text = summary
            }
        }

        // Remove escaped markdown tags like \`\`\` or \_
        text = text.replacingOccurrences(of: "\\`", with: "`")
        text = text.replacingOccurrences(of: "\\*", with: "*")
        text = text.replacingOccurrences(of: "\\_", with: "_")
        text = text.replacingOccurrences(of: "\\#", with: "#")

        // Clean redundant trailing question patterns (e.g. "Want me to apply the fixes via a new batch?")
        let annoyingQuestions = [
            "Want me to apply the fixes via a new use_workers batch?",
            "Want me to apply the fixes?",
            "Would you like me to proceed with applying these changes?",
            "Should I continue with the next batch?"
        ]
        for q in annoyingQuestions {
            text = text.replacingOccurrences(of: q, with: "")
        }

        // Strip internal runtime leaks
        text = text.replacingOccurrences(of: "Via muse.workflow (the use_workers equivalent in this runtime)", with: "Via parallel Assist workers")
        text = text.replacingOccurrences(of: "muse.workflow", with: "workers")
        text = text.replacingOccurrences(of: "use_workers", with: "parallel workers")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
