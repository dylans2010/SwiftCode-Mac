import Foundation

public protocol CloudAuthProviderProtocol: Sendable {
    func getActiveUser() async -> CloudUser?
    func isAuthenticated() async -> Bool
    func getSwiftCodeID() async -> String?
}

public final class CloudAuthProvider: CloudAuthProviderProtocol, @unchecked Sendable {
    public static let shared = CloudAuthProvider()

    private init() {}

    public func getActiveUser() async -> CloudUser? {
        await MainActor.run {
            guard AuthManager.shared.isAuthenticated,
                  let user = AuthManager.shared.currentUser,
                  let swiftCodeID = AuthManager.shared.swiftCodeID else {
                return nil
            }
            return CloudUser(swiftcodeID: swiftCodeID, email: user.email, name: user.name)
        }
    }

    public func isAuthenticated() async -> Bool {
        return await AuthManager.shared.isAuthenticated
    }

    public func getSwiftCodeID() async -> String? {
        return await AuthManager.shared.swiftCodeID
    }
}
