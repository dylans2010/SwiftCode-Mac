import Foundation

public struct ChecklistPlanTool: AgentTool {
    public static let identifier = "checklist_plan"
    public let name = "checklist_plan"
    public let description = "Updates the execution plan checklist."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "tasks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"] as [String: any Sendable],
                        "title": ["type": "string"] as [String: any Sendable],
                        "status": ["type": "string", "enum": ["queued", "in_progress", "completed", "failed"]] as [String: any Sendable],
                        "detail": ["type": "string"] as [String: any Sendable]
                    ] as [String: any Sendable],
                    "required": ["id", "title", "status"]
                ] as [String: any Sendable]
            ] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["tasks"]
    ]

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        return "Checklist updated"
    }
}
