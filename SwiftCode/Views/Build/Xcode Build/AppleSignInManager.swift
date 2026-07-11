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
    public var verificationCode: String = ""

    public enum SessionState: String, Sendable, Codable {
        case signedOut = "Signed Out"
        case loading = "Loading..."
        case requiresTwoFactor = "Verification Code Required"
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

    private struct TempAccountInfo: Sendable, Codable {
        let appleID: String
        let teamName: String
        let teamID: String
        let privateKey: String
    }

    @ObservationIgnored
    private var tempAccountInfo: TempAccountInfo?

    private init() {
        loadAccounts()
    }

    public func sendTwoFactorCode(appleID: String, teamName: String, teamID: String, privateKey: String) async {
        sessionState = .loading
        lastError = nil

        guard !appleID.isEmpty, !teamID.isEmpty, !privateKey.isEmpty else {
            sessionState = .signedOut
            lastError = "All fields are required."
            return
        }

        // Simulate secure verification and trigger code delivery
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        self.tempAccountInfo = TempAccountInfo(
            appleID: appleID,
            teamName: teamName.isEmpty ? "My Apple Team" : teamName,
            teamID: teamID,
            privateKey: privateKey
        )
        self.sessionState = .requiresTwoFactor
    }

    public func verifyTwoFactorCode(_ code: String) async {
        guard let temp = tempAccountInfo else {
            sessionState = .signedOut
            lastError = "Authentication session expired. Please start over."
            return
        }

        sessionState = .loading
        lastError = nil

        // Simulate 2FA code check against Apple Servers
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 6, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: trimmedCode)) else {
            sessionState = .requiresTwoFactor
            lastError = "Invalid verification code. It must be exactly 6 numeric digits."
            return
        }

        // Code verified. Store privateKey securely in Keychain
        let key = "apple_dev_key_\(temp.appleID)_\(temp.teamID)"
        let success = KeychainService.shared.save(temp.privateKey, forKey: key)

        if success {
            let account = AppleDeveloperAccount(
                appleID: temp.appleID,
                teamName: temp.teamName,
                teamID: temp.teamID,
                certificateName: "Apple Development: \(temp.appleID)"
            )
            developerAccounts.append(account)
            selectedTeamID = temp.teamID
            sessionState = .signedIn
            self.tempAccountInfo = nil
            saveAccounts()
        } else {
            sessionState = .signedOut
            lastError = "Failed to store credential in Keychain securely."
        }
    }

    public func addAccount(appleID: String, teamName: String, teamID: String, privateKey: String) async {
        await sendTwoFactorCode(appleID: appleID, teamName: teamName, teamID: teamID, privateKey: privateKey)
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
