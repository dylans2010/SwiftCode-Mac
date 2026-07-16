import Foundation

public final class AssistToolRegistry {
    private var tools: [String: AssistTool] = [:]

    public init() {
        registerAllTools()
    }

    private func registerAllTools() {
        // File System
        register(AssistReadFileTool())
        register(AssistWriteFileTool())
        register(AssistAppendFileTool())
        register(AssistDeleteFileTool())
        register(AssistMoveFileTool())
        register(AssistCopyFileTool())
        register(AssistRenameFileTool())
        register(AssistCreateDirectoryTool())
        register(AssistCreateFileTool())
        register(AssistGenerateFileTool())
        register(AssistDeleteDirectoryTool())
        register(AssistReadDirectoryTool())
        register(AssistTreeViewTool())

        // Search & Analysis
        register(AssistSearchTool())
        register(AssistRegexSearchTool())
        register(AssistSymbolSearchTool())
        register(AssistDependencyGraphTool())
        register(AssistCodeSummaryTool())
        register(AssistLintTool())
        register(AssistComplexityAnalysisTool())

        // Code Editing
        register(AssistReplaceInFileTool())
        register(AssistMultiFileEditTool())
        register(AssistRefactorTool())
        register(AssistFormatCodeTool())
        register(AssistGenerateFileTool())
        register(AssistInsertCodeBlockTool())

        // Snapshot System (Replacing Git)
        register(AssistSnapshotProjectTool())
        register(AssistRestoreSnapshotTool())
        register(AssistDiffTool())
        register(AssistChangeLogTool())
        register(AssistUndoTool())
        register(AssistValidateChangesTool())

        // Execution (Internal Sandbox Only)
        register(AssistTaskRunnerTool())
        register(AssistBuildProjectTool())
        register(AssistTestRunnerTool())
        register(AssistLogCaptureTool())
        register(AssistEnvironmentInfoTool())

        // Intelligence
        register(AssistPlanTaskTool())
        register(AssistBreakdownTaskTool())
        register(AssistAutoFixErrorsTool())
        register(AssistGenerateTestsTool())
        register(AssistExplainCodeTool())

        // Memory
        register(AssistStoreMemoryTool())
        register(AssistRetrieveMemoryTool())
        register(AssistClearMemoryTool())
        register(AssistContextSnapshotTool())

        // Advanced Engineering Infrastructure
        register(AssistSourceGraphBuilder())
        register(AssistSemanticQueryEngine())
        register(AssistCodeMutationEngine())
        register(AssistPatchApplicationEngine())
        register(AssistProjectMutationController())
        register(AssistCompilerDiagnosticsEngine())
        register(AssistAutomatedRepairEngine())
        register(AssistVersionControlOperator())
        register(AssistContextPersistenceStore())
        register(AssistRuntimeDiagnosticsEngine())
        register(AssistExternalResourceGateway())
        register(AssistDependencyResolutionEngine())
        register(AssistAutonomousReviewEngine())
    }

    public func register(_ tool: AssistTool) {
        tools[tool.id] = tool
    }

    public func getTool(_ id: String) -> AssistTool? {
        return tools[id]
    }

    public var allTools: [AssistTool] {
        return Array(tools.values).sorted(by: { $0.id < $1.id })
    }
}
