import Foundation
import SwiftCodeAssistant

/// The sign-in state for the SwiftCode cloud account, ported from
/// Legacy's `AuthManager` (`Services/Appwrite/AuthManager.swift`,
/// 415 lines) onto the REST client.
///
/// Legacy talked to Appwrite through the Apple SDK (`Account`), which
/// kept the session in its own cookie jar and opened OAuth in a web
/// auth session. This manager keeps the same observable state and
/// the same flows, but the transport is `AppwriteAccountClient` and
/// the session secret lives in the secret store
/// (`SecretAccount.appwriteSessionSecret`).
///
/// Differences from Legacy, all deliberate and recorded in
/// `specs/ide/cloud-accounts.md`:
/// - `deleteAccount` works: the REST API supports `DELETE /account`,
///   where the SDK did not (Legacy always threw a 405).
/// - `authError` carries the user-facing message
///   (`AppwriteError.userFacingMessage`, Legacy's
///   `CloudAuthViews.mapErrorToUserMessage` mapping), not the raw
///   server text.
/// - OAuth cannot complete until the app registers the
///   `appwrite-callback-<project>` URL scheme and delivers callbacks
///   to `handleOAuthCallback(_:)`; until then `beginOAuth` waits for
///   a callback that never arrives and times out after 5 minutes
///   instead of pretending the flow finished.
/// - The SwiftCode id is generated with the system random-number
///   generator instead of `SecRandomCopyBytes` (portable; the
///   CryptoKit SHA-256 fallback Legacy had is unnecessary here).
@MainActor
public final class CloudAuthManager {
    public static let shared = CloudAuthManager()

    /// How long `beginOAuth` waits for the app to deliver the
    /// browser callback before giving up.
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
        // Restore the persisted session secret into the client before
        // wiring the change callback, so the initial set does not
        // rewrite the store.
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

    // MARK: - Session restoration

    /// Restores the active Appwrite session when one exists. Reads
    /// the stored session secret, fetches the account, and ensures a
    /// `swiftcode_id` exists in the user's prefs — creating and
    /// storing one when it does not. A failed restore clears all
    /// local state (and the stored user id), exactly as Legacy did.
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
                    // Keep the id locally even when the prefs write
                    // fails; Legacy logged and continued the same way.
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

    // MARK: - Email and password authentication

    /// Signs in with an email address and password, then restores the
    /// session (which fetches the user and ensures `swiftcode_id`).
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

    /// Creates an account and signs in immediately afterward.
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

    // MARK: - OAuth

    /// The browser URL that starts an OAuth2 sign-in for `provider`.
    /// The host opens it (see `beginOAuth`); the provider redirects
    /// back to the `appwrite-callback-<project>://` scheme.
    public func oauthAuthorizeURL(for provider: AppwriteOAuthProvider) -> URL? {
        client.oauthAuthorizeURL(provider: provider)
    }

    /// Starts a Google or GitHub OAuth sign-in: opens the authorize
    /// URL in the browser and waits for the app to deliver the
    /// callback to `handleOAuthCallback(_:)`.
    ///
    /// Honestly unavailable until the app registers the
    /// `appwrite-callback-<project>` URL scheme and forwards opened
    /// URLs here: without that plumbing the wait times out after
    /// `oauthTimeout` (5 minutes) with
    /// `.oauthCallbackTimeout` instead of ever completing. Never
    /// fakes a completed OAuth flow.
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

    /// Delivers a URL the app was opened with on the
    /// `appwrite-callback-<project>` scheme. When a `beginOAuth`
    /// wait is pending, the callback resumes it and this returns nil.
    /// Otherwise the parsed callback is returned for the host to act
    /// on (a recovery or verification link opened from an email).
    /// Returns nil when the URL is not an Appwrite callback at all.
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

    // MARK: - Password recovery

    /// Requests a password reset email.
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

    /// Completes a password reset using the emailed recovery token.
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

    // MARK: - Email verification

    /// Sends a verification email to the current user.
    public func sendVerificationEmail() async throws {
        do {
            let redirectURL = "\(client.configuration.callbackScheme)://verify"
            try await client.createVerification(url: redirectURL)
        } catch {
            throw error
        }
    }

    /// Completes email verification, then restores the session so the
    /// verified state is visible.
    public func verifyEmail(userId: String, secret: String) async throws {
        do {
            try await client.updateVerification(userId: userId, secret: secret)
            await restoreSession()
        } catch {
            throw error
        }
    }

    // MARK: - Account management

    /// Changes the authenticated user's email address.
    public func changeEmail(newEmail: String, password: SecureString) async throws {
        do {
            _ = try await client.updateEmail(email: newEmail, password: password.value())
            await restoreSession()
        } catch {
            throw error
        }
    }

    /// Changes the authenticated user's password.
    public func changePassword(oldPassword: SecureString, newPassword: SecureString) async throws {
        do {
            _ = try await client.updatePassword(password: newPassword.value(), oldPassword: oldPassword.value())
        } catch {
            throw error
        }
    }

    /// Deletes the authenticated user's account. Unlike Legacy —
    /// whose Apple SDK could not expose self-deletion, so
    /// `deleteAccount` always threw a 405 — the REST API supports
    /// `DELETE /account`, so this deletes for real and then clears
    /// local state. Destructive and irreversible.
    public func deleteAccount() async throws {
        do {
            try await client.deleteAccount()
        } catch {
            authError = userFacingMessage(for: error)
            throw error
        }
        clearLocalState()
    }

    /// Ends the active Appwrite session and clears local
    /// authentication state. A server-side failure to end the session
    /// does not stop the local sign-out, as in Legacy.
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

    // MARK: - Stable database user ID

    /// Generates a deterministic UUID from a string using SHA-256.
    public func deterministicUUID(from string: String) -> UUID {
        let hash = SHA256Digest.hash(Data(string.utf8))
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }

    /// Returns a deterministic UUID representing the current user's
    /// database key.
    public func dbUserID(from swiftCodeID: String) -> UUID {
        let cleanID = swiftCodeID
            .replacingOccurrences(of: "sc_id=", with: "")
            .replacingOccurrences(of: "sc_id_", with: "")
        return deterministicUUID(from: cleanID)
    }

    /// Compatibility entry point for existing callers.
    ///
    /// Remote profile synchronization was removed with the external
    /// cloud-profile integration. The authoritative authentication
    /// profile remains in Appwrite.
    @available(*, deprecated, message: "Remote profile synchronization is not configured.")
    public func syncUserProfile() async {
        guard currentUser != nil, swiftCodeID != nil else { return }
    }

    // MARK: - SwiftCode ID generation

    /// Generates a cryptographically secure SwiftCode ID:
    /// `sc_id=` followed by 32 uppercase hex digits from 16 random
    /// bytes. Legacy used `SecRandomCopyBytes`; the system random
    /// number generator is the portable equivalent.
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
