// Moved here from SwiftCodeMCP/CodeReview.swift by MCP-DEP (2026-11-06,
// decision (b) in staging-wire/mcp-dep/DISPOSITIONS.md). Foundation-only struct;
// SwiftCodeAssistant (which cannot import SwiftCodeMCP) needs it for
// AssistManager.currentCodeReview. SwiftCodeMCP keeps using it through
// `import SwiftCodeAssistant`. Body verbatim from the MCP file.

import Foundation

public struct CodeReviewInternalResult: Codable, Sendable {
    public let status: String
    public let summary: String
    public let strengths: [String]
    public let issues: [String]
    public let recommendedFixes: [String]
    public let userSee: String
    public let confidence: Double
}
