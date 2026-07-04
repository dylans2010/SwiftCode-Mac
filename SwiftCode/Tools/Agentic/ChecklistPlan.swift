import Foundation

public struct ChecklistPlanTool: AgentTool {
    public static let identifier = "checklist_plan"
    public let name = "checklist_plan"
    public let description = "Updates the execution plan checklist."
    public let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "tasks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "title": ["type": "string"],
                        "status": ["type": "string", "enum": ["queued", "in_progress", "completed", "failed"]],
                        "detail": ["type": "string"]
                    ],
                    "required": ["id", "title", "status"]
                ]
            ]
        ],
        "required": ["tasks"]
    ]

    public func execute(arguments: [String: Any]) async throws -> String {
        return "Checklist updated"
    }
}
