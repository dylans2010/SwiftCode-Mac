import Foundation

public struct ManageSecretsTool {
    public static let identifier = "manage_secrets"

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
}
