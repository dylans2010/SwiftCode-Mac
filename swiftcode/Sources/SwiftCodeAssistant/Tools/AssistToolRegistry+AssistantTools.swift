import Foundation

extension AssistToolRegistry {
    public func registerAssistantTools() {
        register(AssistReadFileTool())
        register(AssistChangeDirectoryTool())
        register(AssistPrintWorkingDirectoryTool())
        register(AssistTreeViewTool())
        register(AssistCopyFileTool())
        register(AssistMoveFileTool())
        register(AssistDeleteFileTool())
        register(AssistDeleteDirectoryTool())
        register(AssistInsertCodeBlockTool())
        register(AssistMultiFileEditTool())
        register(AssistReplaceInFileTool())
        register(AssistOpenInFinderTool())
        register(AssistRevealInFinderTool())
        register(AssistBuildProjectTool())
        register(AssistGenerateXcodeprojTool())
        register(AssistVersionControlOperator())
        register(UseWorkersTool())
        register(AssistTakeScreenshotTool())
        register(AssistTakeScreenrecordTool())
        register(AssistUseAppTool())
    }
}
