import Foundation

public struct AssistCaptureMemoryTool: AssistTool {
    public let id = "capture_memory"
    public let name = "Capture Memory"
    public let description = "Captures important facts, details about the user, prompting patterns, preferences, etc. and persists them to UserMemory.md."

    public init() {}

    public var capability: ToolCapability { .memory }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Captures important facts, details about the user, prompting patterns, preferences, etc. and persists them in UserMemory.md.",
            properties: [
                "memory": JSONSchema(type: "string", description: "The important fact, user preference, workflow pattern, or detail to remember."),
                "category": JSONSchema(type: "string", description: "Optional category to classify this memory (e.g. 'User Preferences & Profile', 'Project Context', 'Learned Patterns & Directives').")
            ],
            required: ["memory"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard await AssistMemoryStore.shared.isMemoryEnabled else {
            return .failure("User has Memory module OFF.")
        }

        guard let memory = (input["memory"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !memory.isEmpty else {
            return .failure("Missing required parameter: memory")
        }

        let category = (input["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let success = await AssistMemoryStore.shared.capture(memory: memory, category: category)

        if success {
            return .success("Memory captured successfully.", data: [
                "memory": memory,
                "category": category ?? "Learned Patterns & Directives"
            ])
        } else {
            return .failure("Failed to capture memory entry to UserMemory.md.")
        }
    }
}
