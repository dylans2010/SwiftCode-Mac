// AssistToolRegistry+AssistantTools.swift
//
// Enrolment for the tools that live in SwiftCodeAssistant itself.
// (Dylan's own code, direct port authorised under MIT.)
//
// Mirror of `AssistToolRegistry+MCPTools.swift` (SwiftCodeMCP): MCP-defined
// tools enrol in `registerMCPTools()`, called once at MCP startup, because
// SwiftCodeAssistant cannot import SwiftCodeMCP. Assistant-defined tools
// enrol here instead, at registry `init()` time, so BOTH a fresh
// `AssistToolRegistry()` and `.shared` contain them —
// `AssistRuntimeTestSuite` (tests 3, 8b, 26, 35–37) constructs fresh
// registries and resolves tools off `.shared`, so enrolment anywhere else
// would leave those tests looking at an empty registry.
//
// Landed by H-TEST (2026-11-06) alongside the full AssistRuntimeTestSuite
// aggregator. Each tool below was ported verbatim from SwiftCode-Legacy;
// the enrolment list must grow as further Assistant-side tools land.

import Foundation

extension AssistToolRegistry {
    /// Enrols every tool type defined in this target. Idempotent per id:
    /// `register(_:)` keeps the first registration and logs a duplicate,
    /// so calling this twice (fresh registry + `.shared` startup) is safe.
    public func registerAssistantTools() {
        // File reading / navigation
        register(AssistReadFileTool())
        register(AssistChangeDirectoryTool())
        register(AssistPrintWorkingDirectoryTool())
        register(AssistTreeViewTool())
        // File mutation
        register(AssistCopyFileTool())
        register(AssistMoveFileTool())
        register(AssistDeleteFileTool())
        register(AssistDeleteDirectoryTool())
        register(AssistInsertCodeBlockTool())
        register(AssistMultiFileEditTool())
        register(AssistReplaceInFileTool())
        // Finder
        register(AssistOpenInFinderTool())
        register(AssistRevealInFinderTool())
        // Build
        register(AssistBuildProjectTool())
        register(AssistGenerateXcodeprojTool())
        // Version control
        register(AssistVersionControlOperator())
        // Workers / planning
        register(UseWorkersTool())
        // Screen + app interaction (capability .diagnostics / .systemExecution)
        register(AssistTakeScreenshotTool())
        register(AssistTakeScreenrecordTool())
        register(AssistUseAppTool())
    }
}
