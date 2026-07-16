import Foundation

@MainActor
public final class AssistAPIRouter {
    private let context: AssistContext

    public init(context: AssistContext) {
        self.context = context
    }

    public func route(_ request: AssistAPIRequest) async -> AssistAPIResponse {
        switch request.route {
        case .plan:
            return await handlePlan(request)
        case .execute:
            return await handleExecute(request)
        case .analyze:
            return await handleAnalyze(request)
        case .createFile:
            return await handleCreateFile(request)
        case .modifyFile:
            return await handleModifyFile(request)
        case .enhancePrompt:
            return await handleEnhancePrompt(request)
        }
    }

    private func handlePlan(_ request: AssistAPIRequest) async -> AssistAPIResponse {
        guard let intent = request.payload["intent"] else {
            return .failure(error: "Missing intent in payload")
        }
        do {
            let planner = TasksAIPlanner.shared
            let plan = try await planner.generatePlan(intent: intent, context: context)
            let data = try JSONEncoder().encode(plan)
            return .successful(data: ["plan": String(data: data, encoding: .utf8) ?? ""], markdown: "## Plan Generated\n\(plan.goal)")
        } catch {
            return .failure(error: error.localizedDescription)
        }
    }

    private func handleExecute(_ request: AssistAPIRequest) async -> AssistAPIResponse {
        guard let planData = request.payload["plan"]?.data(using: .utf8) else {
            return .failure(error: "Missing plan data in payload")
        }
        do {
            var plan = try JSONDecoder().decode(AssistExecutionPlan.self, from: planData)
            let engine = _AssistCriticalExecutionEngine(context: context)
            try await engine.execute(plan: &plan)
            return .successful(data: ["status": plan.status.rawValue], markdown: "## Execution Complete\nStatus: \(plan.status.rawValue)")
        } catch {
            return .failure(error: error.localizedDescription)
        }
    }

    private func handleAnalyze(_ request: AssistAPIRequest) async -> AssistAPIResponse {
        do {
            let analyzer = _AssistCriticalCodebaseAnalyzer(context: context)
            let summary = try await analyzer.analyze()
            return .successful(data: [
                "totalFiles": "\(summary.totalFiles)",
                "swiftFiles": "\(summary.swiftFileCount)",
                "structure": summary.structure
            ], markdown: "## Codebase Analysis\n\(summary.structure)")
        } catch {
            return .failure(error: error.localizedDescription)
        }
    }

    private func handleCreateFile(_ request: AssistAPIRequest) async -> AssistAPIResponse {
        guard let path = request.payload["path"], let content = request.payload["content"] else {
            return .failure(error: "Missing path or content in payload")
        }
        do {
            try context.fileSystem.writeFile(at: path, content: content)
            return .successful(data: ["path": path], markdown: "## File Created\nCreated \(path)")
        } catch {
            return .failure(error: error.localizedDescription)
        }
    }

    private func handleModifyFile(_ request: AssistAPIRequest) async -> AssistAPIResponse {
        guard let path = request.payload["path"], let content = request.payload["content"] else {
            return .failure(error: "Missing path or content in payload")
        }
        do {
            try context.fileSystem.writeFile(at: path, content: content)
            return .successful(data: ["path": path], markdown: "## File Modified\nModified \(path)")
        } catch {
            return .failure(error: error.localizedDescription)
        }
    }

    private func handleEnhancePrompt(_ request: AssistAPIRequest) async -> AssistAPIResponse {
        guard let userInput = request.payload["userInput"] else {
            return .failure(error: "Missing userInput in payload")
        }
        let enhancedPrompt = await PromptEnhancer.enhancePrompt(userInput: userInput)
        return .successful(data: ["enhancedPrompt": enhancedPrompt], markdown: "## Prompt Enhanced\nOriginal: \(userInput)\nEnhanced: \(enhancedPrompt)")
    }
}
