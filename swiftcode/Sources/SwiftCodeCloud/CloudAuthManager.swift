import Foundation
import SwiftCodeAssistant

@MainActor
public final class CloudAuthManager {
    public static let shared = CloudAuthManager()

    public static let oauthTimeout: TimeInterval = 300

    public private(set) var currentUser: AppwriteUser?
    public private(set) var currentSession: AppwriteSession?
    public private(set) var swiftCodeID: String?
    public private(set) var isAuthenticated = false
    public private(set) var isLoading = false
    public private(set) var authError: String?

    public let client: AppwriteAccountClient
    private let store: any SecretStore

    private var oauthContinuation: CheckedContinuation<AppwriteOAuthCallback, Error>?
    private var oauthContinuationID: UUID?

    public init(
        client: AppwriteAccountClient = AppwriteAccountClient(),
        store: any SecretStore = defaultSecretStore()
    ) {
        var client = client
        self.store = store
        client.sessionSecret = store.readString(SecretAccount.appwriteSessionSecret)
        client.onSessionSecretChanged = { [store] secret in
            if let secret {
                try? store.write(Data(secret.utf8), for: SecretAccount.appwriteSessionSecret)
            } else {
                try? store.delete(SecretAccount.appwriteSessionSecret)
            }
        }
        self.client = client
    }

    public func restoreSession() async {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let user = try await client.getAccount()
            currentUser = user

            if let existingID = user.prefs["swiftcode_id"]?.stringValue, !existingID.isEmpty {
                swiftCodeID = existingID
            } else {
                let newID = generateSwiftCodeID()
                swiftCodeID = newID
                do {
                    _ = try await client.updatePrefs(["swiftcode_id": newID])
                } catch {
                }
            }

            try? store.write(Data(user.id.utf8), for: SecretAccount.appwriteUserID)
            isAuthenticated = true
        } catch {
            currentUser = nil
            currentSession = nil
            swiftCodeID = nil
            isAuthenticated = false
            try? store.delete(SecretAccount.appwriteUserID)
        }
    }

    public func login(email: String, password: SecureString) async throws {
        isLoading = true
        authError = nil

        do {
            let session = try await client.createEmailPasswordSession(email: email, password: password.value())
            currentSession = session
            await restoreSession()
        } catch {
            authError = userFacingMessage(for: error)
            isLoading = false
            throw error
        }
    }

    public func createAccount(email: String, password: SecureString) async throws {
        isLoading = true
        authError = nil

        do {
            _ = try await client.createAccount(userId: "unique()", email: email, password: password.value())
            try await login(email: email, password: password)
        } catch {
            authError = userFacingMessage(for: error)
            isLoading = false
            throw error
        }
    }

    public func oauthAuthorizeURL(for provider: AppwriteOAuthProvider) -> URL? {
        client.oauthAuthorizeURL(provider: provider)
    }

    public func beginOAuth(
        provider: AppwriteOAuthProvider,
        openURL: @escaping @Sendable (URL) -> Bool
    ) async throws -> AppwriteUser {
        isLoading = true
        authError = nil

        guard let url = oauthAuthorizeURL(for: provider) else {
            isLoading = false
            throw AppwriteError.invalidConfiguration("Cannot build the OAuth authorize URL.")
        }
        guard openURL(url) else {
            isLoading = false
            throw AppwriteError.oauthFailed("SwiftCode could not open the browser.")
        }

        let callback: AppwriteOAuthCallback
        do {
            callback = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppwriteOAuthCallback, Error>) in
                let id = UUID()
                oauthContinuation = continuation
                oauthContinuationID = id
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(Self.oauthTimeout * 1_000_000_000))
                    if self.oauthContinuationID == id, let pending = self.oauthContinuation {
                        self.oauthContinuation = nil
                        self.oauthContinuationID = nil
                        pending.resume(throwing: AppwriteError.oauthCallbackTimeout)
                    }
                }
            }
        } catch {
            authError = userFacingMessage(for: error)
            isLoading = false
            throw error
        }

        switch callback {
        case .success:
            await restoreSession()
            isLoading = false
            guard let user = currentUser else {
                throw AppwriteError.oauthFailed("The sign-in finished but no account could be loaded.")
            }
            return user
        case .failure(let message):
            let error = AppwriteError.oauthFailed(message ?? "The provider declined the sign-in.")
            authError = error.userFacingMessage
            isLoading = false
            throw error
        case .recovery, .verification:
            let error = AppwriteError.oauthFailed("The app received a recovery or verification link while waiting for a sign-in.")
            authError = error.userFacingMessage
            isLoading = false
            throw error
        }
    }

    @discardableResult
    public func handleOAuthCallback(_ url: URL) -> AppwriteOAuthCallback? {
        guard let callback = client.parseOAuthCallback(url) else { return nil }
        if let pending = oauthContinuation {
            oauthContinuation = nil
            oauthContinuationID = nil
            pending.resume(returning: callback)
            return nil
        }
        return callback
    }

    public func forgotPassword(email: String) async throws {
        isLoading = true
        authError = nil

        do {
            let redirectURL = "\(client.configuration.callbackScheme)://reset-password"
            try await client.createRecovery(email: email, url: redirectURL)
            isLoading = false
        } catch {
            authError = userFacingMessage(for: error)
            isLoading = false
            throw error
        }
    }

    public func resetPassword(userId: String, secret: String, password: SecureString) async throws {
        isLoading = true
        authError = nil

        do {
            try await client.updateRecovery(userId: userId, secret: secret, password: password.value())
            isLoading = false
        } catch {
            authError = userFacingMessage(for: error)
            isLoading = false
            throw error
        }
    }

    public func sendVerificationEmail() async throws {
        do {
            let redirectURL = "\(client.configuration.callbackScheme)://verify"
            try await client.createVerification(url: redirectURL)
        } catch {
            throw error
        }
    }

    public func verifyEmail(userId: String, secret: String) async throws {
        do {
            try await client.updateVerification(userId: userId, secret: secret)
            await restoreSession()
        } catch {
            throw error
        }
    }

    public func changeEmail(newEmail: String, password: SecureString) async throws {
        do {
            _ = try await client.updateEmail(email: newEmail, password: password.value())
            await restoreSession()
        } catch {
            throw error
        }
    }

    public func changePassword(oldPassword: SecureString, newPassword: SecureString) async throws {
        do {
            _ = try await client.updatePassword(password: newPassword.value(), oldPassword: oldPassword.value())
        } catch {
            throw error
        }
    }

    public func deleteAccount() async throws {
        do {
            try await client.deleteAccount()
        } catch {
            authError = userFacingMessage(for: error)
            throw error
        }
        clearLocalState()
    }

    public func logout() async {
        isLoading = true
        authError = nil
        try? await client.deleteSession(sessionId: "current")
        clearLocalState()
        isLoading = false
    }

    private func clearLocalState() {
        currentUser = nil
        currentSession = nil
        swiftCodeID = nil
        isAuthenticated = false
        try? store.delete(SecretAccount.appwriteUserID)
    }

    public func deterministicUUID(from string: String) -> UUID {
        let hash = SHA256Digest.hash(Data(string.utf8))
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }

    public func dbUserID(from swiftCodeID: String) -> UUID {
        let cleanID = swiftCodeID
            .replacingOccurrences(of: "sc_id=", with: "")
            .replacingOccurrences(of: "sc_id_", with: "")
        return deterministicUUID(from: cleanID)
    }

    @available(*, deprecated, message: "Remote profile synchronization is not configured.")
    public func syncUserProfile() async {
        guard currentUser != nil, swiftCodeID != nil else { return }
    }

    private func generateSwiftCodeID() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) }
        let hexString = bytes.map { String(format: "%02X", $0) }.joined()
        return "sc_id=\(hexString)"
    }

    private func userFacingMessage(for error: Error) -> String {
        (error as? AppwriteError)?.userFacingMessage ?? error.localizedDescription
    }
}
