import Foundation
import SwiftCodeAssistant

extension AssistToolRegistry {
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
