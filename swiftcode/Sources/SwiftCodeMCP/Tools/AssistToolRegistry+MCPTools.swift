// MCP-side enrolment for AssistToolRegistry (SwiftCodeAssistant).
// Created by MCP-DEP (2026-11-06, decision (b) in staging-wire/mcp-dep/DISPOSITIONS.md).
// The registry mechanics moved to SwiftCodeAssistant, which cannot import this
// target, so the tools defined HERE enrol themselves through this function.
// The 19 types below are exactly the `registerAllTools()` entries whose types
// exist in the tree (checked 2026-11-06; +2 in this wave:
// `AssistFetchDocumentationTool`, `AssistGitHubRepoTool`); the other ~272 entries reference
// tools that exist nowhere yet and enrol via register(_:) as they land.
// Wiring: call `AssistToolRegistry.shared.registerMCPTools()` once at MCP
// startup (e.g. from MCPServer initialisation) — no call site is added here
// because MCPServer's init is owned by the MCP wiring scope.

import Foundation
import SwiftCodeAssistant

extension AssistToolRegistry {
    /// Registers every AssistTool implementation defined in SwiftCodeMCP.
    public func registerMCPTools() {
        register(AssistArtboardCompileTool())
        register(AssistChangeLogTool())
        register(AssistContextSnapshotTool())
        register(AssistConversationContextTool())
        register(AssistExplainCodeTool())
        register(AssistFetchDocumentationTool())
        register(AssistFixArtboardsTool())
        register(AssistGitHubRepoTool())
        register(AssistSaveToMemoryTool())
        register(AssistSwiftASTInspectorTool())
        register(AssistTakeScreenshotTool())
        register(AssistUndoTool())
        register(AssistViewMemoryTool())
        register(AssistXcodeBuildSettingsTool())
        register(CodeReviewTool())
        register(PlanAskUserTool())
        register(ReverseToolAdapter())
        register(UseTermFunction())
        register(UseWorkersTool())
    }
}
