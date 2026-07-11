import Foundation
import Observation
import Security

@Observable
@MainActor
public final class AppleSignInManager: Sendable {
    public static let shared = AppleSignInManager()

    public var developerAccounts: [AppleDeveloperAccount] = []
    public var selectedTeamID: String?
    public var sessionState: SessionState = .signedOut
    public var lastError: String?

    public enum SessionState: String, Sendable, Codable {
        case signedOut = "Signed Out"
        case loading = "Loading..."
        case signedIn = "Signed In"
        case expired = "Session Expired"
    }

    public struct AppleDeveloperAccount: Identifiable, Sendable, Codable {
        public var id: String { appleID }
        public let appleID: String
        public let teamName: String
        public let teamID: String
        public let certificateName: String
    }

    private init() {
        loadAccounts()
    }

    public func addAccount(appleID: String, teamName: String, teamID: String, privateKey: String) async {
        sessionState = .loading
        lastError = nil

        guard !appleID.isEmpty, !teamID.isEmpty, !privateKey.isEmpty else {
            sessionState = .signedOut
            lastError = "All fields are required."
            return
        }

        // Store privateKey securely in Keychain
        let key = "apple_dev_key_\(appleID)_\(teamID)"
        let success = KeychainService.shared.save(privateKey, forKey: key)

        if success {
            let account = AppleDeveloperAccount(
                appleID: appleID,
                teamName: teamName.isEmpty ? "My Apple Team" : teamName,
                teamID: teamID,
                certificateName: "Apple Development: \(appleID)"
            )
            developerAccounts.append(account)
            selectedTeamID = teamID
            sessionState = .signedIn
            saveAccounts()
        } else {
            sessionState = .signedOut
            lastError = "Failed to store credential in Keychain securely."
        }
    }

    public func removeAccount(at indexSet: IndexSet) {
        for index in indexSet {
            let account = developerAccounts[index]
            let key = "apple_dev_key_\(account.appleID)_\(account.teamID)"
            _ = KeychainService.shared.delete(forKey: key)
        }
        developerAccounts.remove(atOffsets: indexSet)
        if developerAccounts.isEmpty {
            sessionState = .signedOut
            selectedTeamID = nil
        } else {
            selectedTeamID = developerAccounts.first?.teamID
        }
        saveAccounts()
    }

    // MARK: - Persistence

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(developerAccounts) {
            UserDefaults.standard.set(data, forKey: "apple_developer_accounts")
        }
    }

    private func loadAccounts() {
        if let data = UserDefaults.standard.data(forKey: "apple_developer_accounts"),
           let decoded = try? JSONDecoder().decode([AppleDeveloperAccount].self, from: data) {
            developerAccounts = decoded
            if !developerAccounts.isEmpty {
                sessionState = .signedIn
                selectedTeamID = developerAccounts.first?.teamID
            }
        }
    }
}
