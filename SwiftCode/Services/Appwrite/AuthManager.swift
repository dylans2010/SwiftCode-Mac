import Foundation
import Appwrite
import JSONCodable
import CryptoKit
import os

private let logger = Logger(subsystem: "com.swiftcode.Auth", category: "AuthManager")

@MainActor
@Observable
public final class AuthManager {
    public static let shared = AuthManager()

    // Thread-safe observable state
    public private(set) var currentUser: Appwrite.User<[String: AnyCodable]>?
    public private(set) var currentSession: Appwrite.Session?
    public private(set) var swiftCodeID: String?
    public private(set) var isAuthenticated = false
    public private(set) var isLoading = false
    public private(set) var authError: String?

    // Access to Client and Account instances
    public let client: Client
    public let account: Account

    private init() {
        self.client = SwiftCode.client
        self.account = SwiftCode.account
    }

    /// Restore the active session on application launch if one exists.
    public func restoreSession() async {
        isLoading = true
        authError = nil
        logger.info("Starting session restoration from Appwrite...")

        do {
            let user = try await account.get()
            self.currentUser = user

            // Retrieve existing SwiftCode ID or generate a new one if it doesn't exist yet
            if let existingID = user.prefs.data["swiftcode_id"]?.value as? String {
                self.swiftCodeID = existingID
                logger.info("Successfully retrieved existing SwiftCode ID: \(existingID)")
            } else {
                let newID = generateSwiftCodeID()
                self.swiftCodeID = newID
                logger.info("No SwiftCode ID found. Generated new secure ID: \(newID)")
                do {
                    _ = try await account.updatePrefs(prefs: ["swiftcode_id": newID])
                    logger.info("Successfully stored new SwiftCode ID to Appwrite preferences.")
                } catch {
                    logger.error("Failed to store SwiftCode ID to Appwrite preferences: \(error.localizedDescription)")
                }
            }

            self.isAuthenticated = true
            logger.info("Session restoration succeeded for user: \(user.email)")

            /// Synchronize the profile deterministically in Supabase
            Task {
                await self.syncUserProfile()
            }
        } catch {
            self.currentUser = nil
            self.swiftCodeID = nil
            self.isAuthenticated = false
            logger.debug("No active Appwrite session restored: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Sign in using an email and password.
    public func login(email: String, password: SecureString) async throws {
        isLoading = true
        authError = nil
        logger.info("Initiating email/password sign-in...")

        do {
            let session = try await account.createEmailPasswordSession(
                email: email,
                password: password.value()
            )
            self.currentSession = session
            await restoreSession()
            logger.info("Email/password sign-in succeeded.")
        } catch {
            authError = error.localizedDescription
            logger.error("Email/password sign-in failed: \(error.localizedDescription)")
            isLoading = false
            throw error
        }
    }

    /// Create a new account with email and password.
    public func createAccount(email: String, password: SecureString) async throws {
        isLoading = true
        authError = nil
        logger.info("Initiating account creation...")

        do {
            _ = try await account.create(
                userId: ID.unique(),
                email: email,
                password: password.value()
            )
            logger.info("Account creation succeeded. Initiating session sign-in...")

            // Log in immediately after registration
            try await login(email: email, password: password)
        } catch {
            authError = error.localizedDescription
            logger.error("Account creation or initial login failed: \(error.localizedDescription)")
            isLoading = false
            throw error
        }
    }

    /// Initiate Google OAuth flow.
    public func loginWithGoogle() async throws {
        isLoading = true
        authError = nil
        logger.info("Initiating Google OAuth flow...")

        do {
            let callbackScheme = "appwrite-callback-6a670d0b0022e5f964b4://"
            _ = try await account.createOAuth2Session(
                provider: .google,
                success: callbackScheme,
                failure: callbackScheme
            )
            await restoreSession()
            logger.info("Google OAuth login session completed.")
        } catch {
            authError = error.localizedDescription
            logger.error("Google OAuth flow failed: \(error.localizedDescription)")
            isLoading = false
            throw error
        }
    }

    /// Initiate GitHub OAuth flow.
    public func loginWithGitHub() async throws {
        isLoading = true
        authError = nil
        logger.info("Initiating GitHub OAuth flow...")

        do {
            let callbackScheme = "appwrite-callback-6a670d0b0022e5f964b4://"
            _ = try await account.createOAuth2Session(
                provider: .github,
                success: callbackScheme,
                failure: callbackScheme
            )
            await restoreSession()
            logger.info("GitHub OAuth login session completed.")
        } catch {
            authError = error.localizedDescription
            logger.error("GitHub OAuth flow failed: \(error.localizedDescription)")
            isLoading = false
            throw error
        }
    }

    /// Request a password reset link.
    public func forgotPassword(email: String) async throws {
        isLoading = true
        authError = nil
        logger.info("Requesting password reset for: \(email)")

        do {
            let redirectURL = "appwrite-callback-6a670d0b0022e5f964b4://reset-password"
            _ = try await account.createRecovery(
                email: email,
                url: redirectURL
            )
            logger.info("Password reset request submitted successfully.")
            isLoading = false
        } catch {
            authError = error.localizedDescription
            logger.error("Password reset request failed: \(error.localizedDescription)")
            isLoading = false
            throw error
        }
    }

    /// Complete a password reset using the token/secret sent by email.
    public func resetPassword(userId: String, secret: String, password: SecureString) async throws {
        isLoading = true
        authError = nil
        logger.info("Resetting password for userId: \(userId)")

        do {
            _ = try await account.updateRecovery(
                userId: userId,
                secret: secret,
                password: password.value()
            )
            logger.info("Password reset successfully completed.")
            isLoading = false
        } catch {
            authError = error.localizedDescription
            logger.error("Password reset failed: \(error.localizedDescription)")
            isLoading = false
            throw error
        }
    }

    /// Send a verification email to the user.
    public func sendVerificationEmail() async throws {
        logger.info("Requesting verification email...")
        do {
            let redirectURL = "appwrite-callback-6a670d0b0022e5f964b4://verify"
            _ = try await account.createVerification(url: redirectURL)
            logger.info("Verification email sent successfully.")
        } catch {
            logger.error("Failed to send verification email: \(error.localizedDescription)")
            throw error
        }
    }

    /// Complete email verification.
    public func verifyEmail(userId: String, secret: String) async throws {
        logger.info("Verifying email with secret...")
        do {
            _ = try await account.updateVerification(userId: userId, secret: secret)
            logger.info("Email verification successfully completed.")
            await restoreSession()
        } catch {
            logger.error("Failed to complete email verification: \(error.localizedDescription)")
            throw error
        }
    }

    /// Change email address of the current authenticated user.
    public func changeEmail(newEmail: String, password: SecureString) async throws {
        logger.info("Updating email address to: \(newEmail)")
        do {
            _ = try await account.updateEmail(email: newEmail, password: password.value())
            logger.info("Email address updated successfully.")
            await restoreSession()
        } catch {
            logger.error("Failed to update email address: \(error.localizedDescription)")
            throw error
        }
    }

    /// Change password of the current authenticated user.
    public func changePassword(oldPassword: SecureString, newPassword: SecureString) async throws {
        logger.info("Updating user password...")
        do {
            _ = try await account.updatePassword(password: newPassword.value(), oldPassword: oldPassword.value())
            logger.info("Password updated successfully.")
        } catch {
            logger.error("Failed to update password: \(error.localizedDescription)")
            throw error
        }
    }

    /// Delete the current authenticated account from the server.
    public func deleteAccount() async throws {
        logger.warning("Account self-deletion is not supported from client applications in the Appwrite Apple SDK.")
        throw NSError(
            domain: "AuthManager",
            code: 405,
            userInfo: [NSLocalizedDescriptionKey: "Account deletion is not supported from client applications. Please contact support or delete your account via the developer console."]
        )
    }

    /// Securely log out the active user session.
    public func logout() async {
        isLoading = true
        authError = nil
        logger.info("Logging out active session...")

        do {
            _ = try await account.deleteSession(sessionId: "current")
            logger.info("Appwrite active session successfully terminated.")
        } catch {
            logger.error("Failed to terminate active Appwrite session: \(error.localizedDescription)")
        }

        self.currentUser = nil
        self.currentSession = nil
        self.swiftCodeID = nil
        self.isAuthenticated = false
        self.isLoading = false

        / Sign out from Supabase Auth as well
        Task {
            try? await SupabaseProvider.shared.signOutFromSupabase()
        }
    }

    /// Generates a deterministic UUID from any String (such as Appwrite user ID) using SHA256.
    public func deterministicUUID(from string: String) -> UUID {
        let hash = SHA256.hash(data: Data(string.utf8))
        let bytes = Array(hash)
        let uuidBytes = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidBytes)
    }

    /// Returns the deterministic UUID representing the current user's DB key.
    public func dbUserID(from swiftCodeID: String) -> UUID {
        let cleanID = swiftCodeID.replacingOccurrences(of: "sc_id=", with: "")
                                 .replacingOccurrences(of: "sc_id_", with: "")
        return deterministicUUID(from: cleanID)
    }

    /// Synchronizes the user's backend profile in Supabase with the latest authentication details.
    public func syncUserProfile() async {
        guard let user = currentUser, let swiftCodeID = swiftCodeID else { return }

        let dbUserID = dbUserID(from: swiftCodeID)

        logger.info("Synchronizing user profile to Supabase...")

        do {
            try await SupabaseProvider.shared.registerShadowUser(id: dbUserID, email: user.email)
            try await SupabaseProvider.shared.signInToSupabase(id: dbUserID, email: user.email)
        } catch {
            logger.error("Failed to register/sign-in shadow user: \(error.localizedDescription)")
            return
        }

        let profileUpdate: [String: AnyCodable] = [
            "display_name": AnyCodable(user.name),
            "avatar_url": AnyCodable(""),
            "auth_provider": AnyCodable("appwrite"),
            "last_sign_in": AnyCodable(ISO8601DateFormatter().string(from: Date())),
            "last_active": AnyCodable(ISO8601DateFormatter().string(from: Date())),
            "account_status": AnyCodable("active"),
            "email_verified": AnyCodable(user.emailVerification),
            "cloud_enabled": AnyCodable(true),
            "backup_enabled": AnyCodable(true),
            "ai_enabled": AnyCodable(true),
            "sync_statistics": AnyCodable("{}")
        ]

        do {
            try await SupabaseProvider.shared.updateProfile(id: dbUserID, values: profileUpdate)
            logger.info("Successfully updated user profile in Supabase.")
        } catch {
            logger.error("Failed to update user profile in Supabase: \(error.localizedDescription)")
        }
    }

    // MARK: - SwiftCode ID Generator

    /// Generates a cryptographically secure, unpredictable, globally unique SwiftCode ID.
    private func generateSwiftCodeID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hexString: String
        if status == errSecSuccess {
            hexString = bytes.map { String(format: "%02X", $0) }.joined()
        } else {
            // Secure fallback using CryptoKit SHA256 of a random UUID & system uptime
            let fallbackUUID = UUID().uuidString + "\(ProcessInfo.processInfo.systemUptime)"
            let hash = SHA256.hash(data: Data(fallbackUUID.utf8))
            hexString = hash.compactMap { String(format: "%02X", $0) }.prefix(32).joined()
        }
        return "sc_id=\(hexString)"
    }
}
