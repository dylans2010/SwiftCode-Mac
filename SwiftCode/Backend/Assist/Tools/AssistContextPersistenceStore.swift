import Foundation

public struct AssistContextPersistenceStore: AssistTool {
    public let id = "context_persistence_store"
    public let name = "Persistent Context Store"
    public let description = "Stores and retrieves persistent key-value context across Assist sessions."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let action = (input["action"] as? String ?? "get").lowercased()
        guard let key = input["key"] as? String, !key.isEmpty else { return .failure("Missing key") }

        let file = context.workspaceRoot.appendingPathComponent(".assist_context_store.json")
        var db: [String: String] = [:]
        if let existing = try? Data(contentsOf: file),
           let json = try? JSONSerialization.jsonObject(with: existing) as? [String: String] {
            db = json
        }

        switch action {
        case "set":
            guard let value = input["value"] as? String else { return .failure("Missing value") }
            db[key] = value
            let data = try JSONSerialization.data(withJSONObject: db, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: file, options: .atomic)
            return .success("Stored context for key \(key)")
        case "delete":
            db.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: db, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: file, options: .atomic)
            return .success("Deleted key \(key)")
        default:
            return .success("Retrieved context for key \(key)", data: ["value": db[key] ?? ""])
        }
    }
}
