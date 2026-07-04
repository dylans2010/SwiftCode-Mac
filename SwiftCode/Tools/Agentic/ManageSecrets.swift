import Foundation

public struct ManageSecretsTool: AgentTool {
    public static let identifier = "manage_secrets"
    public let name = "manage_secrets"
    public let description = "Manages secrets in the keychain."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "action": ["type": "string", "enum": ["save", "get"]] as [String: any Sendable],
            "key": ["type": "string"] as [String: any Sendable],
            "value": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["action", "key"]
    ]

    public func run(action: String, key: String, value: String?) async throws -> String? {
        switch action {
        case "save":
            if let val = value { try await KeychainService.shared.save(account: key, value: val) }
            return "Secret saved"
        case "get":
            return try await KeychainService.shared.get(account: key)
        default:
            return nil
        }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let action = arguments["action"] as? String,
              let key = arguments["key"] as? String else {
            throw AgentError.toolError("Missing action or key")
        }
        let value = arguments["value"] as? String
        let result = try await run(action: action, key: key, value: value)
        return result ?? "No result"
    }
}
