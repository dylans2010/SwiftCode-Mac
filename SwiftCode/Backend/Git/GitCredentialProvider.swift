import Foundation

public actor GitCredentialProvider {
    public static let shared = GitCredentialProvider()

    public func getPAT() async throws -> String? {
        return try await KeychainService.shared.get(account: "github-pat")
    }

    public func savePAT(_ token: String) async throws {
        try await KeychainService.shared.save(account: "github-pat", value: token)
    }
}
