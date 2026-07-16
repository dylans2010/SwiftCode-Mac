import Foundation
import Combine

/// A high-trust task planning engine that decomposes user intent into executable steps.
@MainActor
public final class TasksAIPlanner: ObservableObject {
    public static let shared = TasksAIPlanner()

    @Published public var currentPlan: AssistExecutionPlan?
    @Published public var isPlanning = false

    private init() {}

    /// Generates a structured multi-step plan based on user intent.
    public func generatePlan(intent: String, context: AssistContext) async throws -> AssistExecutionPlan {
        isPlanning = true
        defer { isPlanning = false }

        await context.logger.info("Generating autonomous plan for intent: \(intent)", toolId: "TasksAIPlanner")

        let prompt = """
        \(AssistAgenticPrompt.systemPrompt)

        # TASK
        Analyze the user's intent and generate a structured execution plan for an iOS application.
        Intent: "\(intent)"

        # RESPONSE REQUIREMENTS
        You must output a VALID JSON object representing the plan. Do not include any text before or after the JSON.

        JSON SCHEMA:
        {
          "goal": "Clear summary of the goal",
          "steps": [
            {
              "toolId": "The ID of the tool to use",
              "description": "Clear description of what this step achieves",
              "input": { "key": "value" }
            }
          ]
        }

        # AVAILABLE TOOLS
        - file_read (input: { "path": "..." })
        - file_write (input: { "path": "...", "content": "..." })
        - file_create (input: { "path": "...", "content": "...", "overwrite": "false" })
        - search_text (input: { "pattern": "..." })
        - code_refactor (input: { "path": "...", "action": "..." })
        - project_build (input: { "project": "..." })
        - project_test (input: { "path": "..." })
        - tree_view (input: { "path": "...", "maxDepth": "3" })

        # EXAMPLES
        User: "Add a login screen"
        Response:
        {
          "goal": "Implement a new SwiftUI LoginView and integrate it.",
          "steps": [
            { "toolId": "tree_view", "description": "Explore project structure.", "input": { "path": "." } },
            { "toolId": "file_write", "description": "Create LoginView.swift", "input": { "path": "Views/LoginView.swift", "content": "import SwiftUI..." } },
            { "toolId": "project_build", "description": "Verify build.", "input": { "project": "SwiftCode.xcodeproj" } }
          ]
        }

        # ADVANCED TOOL PREFERENCE
        Prefer explicit tool-driven execution over direct generation. Use these when relevant:
        - source_graph_builder
        - semantic_query_engine
        - code_mutation_engine
        - patch_application_engine
        - project_mutation_controller
        - compiler_diagnostics_engine
        - automated_repair_engine
        - version_control_operator
        - context_persistence_store
        - runtime_diagnostics_engine
        - external_resource_gateway
        - dependency_resolution_engine
        - autonomous_review_engine

        # CONSTRAINTS
        - Minimum 3 steps.
        - Never return an empty steps array.
        - Use real file paths and FULL, production-ready implementations.
        - No mock data.
        - Every step must have a real toolId from available tools.

        # FINAL REPORT FORMAT
        All plans must lead to a final report following the markdown structure:
        ## Plan
        ## Execution Progress
        ## Files Modified
        ## Iteration Notes
        ## Result
        ## Next Actions
        """

        let modelID = AssistModelManager.shared.selectedModelID
        let providerRawValue = UserDefaults.standard.string(forKey: "assist.selectedProvider") ?? AssistModelProvider.openAI.rawValue
        let provider = AssistModelProvider(rawValue: providerRawValue) ?? .openAI
        let apiKey = APIKeyManager.shared.retrieveKey(service: provider.apiKeyProvider)

        let response = await AssistLLMService.generateResponse(
            prompt: prompt,
            provider: provider,
            apiKey: apiKey,
            modelOverride: modelID
        )

        guard response.success else {
            await context.logger.error("Planner failed to get AI response: \(response.error ?? "Unknown error")", toolId: "TasksAIPlanner")
            return fallbackPlan(intent: intent)
        }

        do {
            let plan = try parsePlan(from: response.content)
            self.currentPlan = plan
            return plan
        } catch {
            await context.logger.error("Failed to parse plan JSON: \(error.localizedDescription)", toolId: "TasksAIPlanner")
            return fallbackPlan(intent: intent)
        }
    }

    /// Provides a basic fallback plan if the AI fails to generate one.
    public func fallbackPlan(intent: String) -> AssistExecutionPlan {
        var plan = AssistExecutionPlan(goal: intent)
        plan.steps = [
            AssistExecutionStep(toolId: "search_text", input: ["pattern": intent], description: "Search codebase for context related to intent."),
            AssistExecutionStep(toolId: "tree_view", input: ["path": "."], description: "Explore project structure."),
            AssistExecutionStep(toolId: "file_create", input: ["path": "AssistNotes.md", "content": "# Assist Plan\n\nIntent: \(intent)"], description: "Create a working notes file so execution can continue even when referenced files are missing.")
        ]
        self.currentPlan = plan
        return plan
    }

    /// Updates the status of a specific step in the current plan.
    public func updateStep(id: UUID, status: AssistExecutionStatus, result: AssistToolResult? = nil) {
        guard var plan = currentPlan else { return }
        if let index = plan.steps.firstIndex(where: { $0.id == id }) {
            plan.steps[index].status = status
            if let result = result {
                plan.steps[index].result = result
            }
            self.currentPlan = plan
        }
    }

    private func parsePlan(from response: String) throws -> AssistExecutionPlan {
        // Find JSON block (handles ```json ... ``` or just { ... })
        // Use non-greedy regex to avoid capturing multiple JSON blocks
        var jsonStr = response
        if let range = response.range(of: "\\{[^}]*\\}", options: .regularExpression, range: nil, locale: nil) {
            jsonStr = String(response[range])
        }

        guard let data = jsonStr.data(using: .utf8) else {
            throw AssistPlannerError.invalidResponse
        }

        do {
            struct RawPlan: Decodable {
                let goal: String
                let steps: [RawStep]
            }
            struct RawStep: Decodable {
                let toolId: String
                let description: String
                let input: [String: String]
            }

            let raw = try JSONDecoder().decode(RawPlan.self, from: data)

            guard !raw.steps.isEmpty else {
                throw AssistPlannerError.invalidResponse
            }

            var plan = AssistExecutionPlan(goal: raw.goal)
            plan.steps = raw.steps.map { step in
                AssistExecutionStep(
                    toolId: step.toolId,
                    input: step.input,
                    description: step.description
                )
            }
            return plan
        } catch {
            // Last ditch attempt: if it's a simple list but not proper JSON, try to extract goal at least
            if response.contains("goal") {
                 return fallbackPlan(intent: "Refined Task: \(jsonStr.prefix(100))...")
            }
            throw error
        }
    }
}
