import Foundation
import Appwrite
import JSONCodable
import CryptoKit
import Security
import os

private let logger = Logger(
    subsystem: "com.swiftcode.Auth",
    category: "AuthManager"
)

@MainActor
@Observable
public final class AuthManager {
    public static let shared = AuthManager()

    public private(set) var currentUser: Appwrite.User<[String: AnyCodable]>?
    public private(set) var currentSession: Appwrite.Session?
    public private(set) var swiftCodeID: String?
    public private(set) var isAuthenticated = false
    public private(set) var isLoading = false
    public private(set) var authError: String?

    public let client: Client
    public let account: Account

    private init() {
        self.client = SwiftCode.client
        self.account = SwiftCode.account
    }

    public func restoreSession() async {
        isLoading = true
        authError = nil
        logger.info("Starting session restoration from Appwrite...")

        defer { isLoading = false }

        do {
            let user = try await account.get()
            currentUser = user

            if let existingID = user.prefs.data["swiftcode_id"]?.value as? String,
               !existingID.isEmpty {
                swiftCodeID = existingID
                logger.info("Retrieved the existing SwiftCode ID.")
            } else {
                let newID = generateSwiftCodeID()
                swiftCodeID = newID

                do {
                    _ = try await account.updatePrefs(
                        prefs: ["swiftcode_id": newID]
                    )
                    logger.info("Stored a new SwiftCode ID in Appwrite preferences.")
                } catch {
                    logger.error(
                        "Failed to store SwiftCode ID in Appwrite preferences: \(error.localizedDescription)"
                    )
                }
            }

            isAuthenticated = true
            logger.info("Session restoration succeeded for user: \(user.email)")
        } catch {
            currentUser = nil
            currentSession = nil
            swiftCodeID = nil
            isAuthenticated = false
            logger.debug(
                "No active Appwrite session restored: \(error.localizedDescription)"
            )
        }
    }

    public func login(email: String, password: SecureString) async throws {
        isLoading = true
        authError = nil
        logger.info("Initiating email/password sign-in...")

        do {
            let session = try await account.createEmailPasswordSession(
                email: email,
                password: password.value()
            )
            currentSession = session
            await restoreSession()
            logger.info("Email/password sign-in succeeded.")
        } catch {
            authError = error.localizedDescription
            isLoading = false
            logger.error(
                "Email/password sign-in failed: \(error.localizedDescription)"
            )
            throw error
        }
    }

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

            logger.info("Account creation succeeded. Signing in...")
            try await login(email: email, password: password)
        } catch {
            authError = error.localizedDescription
            isLoading = false
            logger.error(
                "Account creation or initial sign-in failed: \(error.localizedDescription)"
            )
            throw error
        }
    }

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
            logger.info("Google OAuth flow completed.")
        } catch {
            authError = error.localizedDescription
            isLoading = false
            logger.error("Google OAuth flow failed: \(error.localizedDescription)")
            throw error
        }
    }

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
            logger.info("GitHub OAuth flow completed.")
        } catch {
            authError = error.localizedDescription
            isLoading = false
            logger.error("GitHub OAuth flow failed: \(error.localizedDescription)")
            throw error
        }
    }

    public func forgotPassword(email: String) async throws {
        isLoading = true
        authError = nil

        do {
            let redirectURL =
                "appwrite-callback-6a670d0b0022e5f964b4://reset-password"
            _ = try await account.createRecovery(
                email: email,
                url: redirectURL
            )
            logger.info("Password reset request submitted.")
            isLoading = false
        } catch {
            authError = error.localizedDescription
            isLoading = false
            logger.error(
                "Password reset request failed: \(error.localizedDescription)"
            )
            throw error
        }
    }

    public func resetPassword(
        userId: String,
        secret: String,
        password: SecureString
    ) async throws {
        isLoading = true
        authError = nil

        do {
            _ = try await account.updateRecovery(
                userId: userId,
                secret: secret,
                password: password.value()
            )
            logger.info("Password reset completed.")
            isLoading = false
        } catch {
            authError = error.localizedDescription
            isLoading = false
            logger.error("Password reset failed: \(error.localizedDescription)")
            throw error
        }
    }

    public func sendVerificationEmail() async throws {
        logger.info("Requesting verification email...")

        do {
            let redirectURL = "appwrite-callback-6a670d0b0022e5f964b4://verify"
            _ = try await account.createVerification(url: redirectURL)
            logger.info("Verification email sent.")
        } catch {
            logger.error(
                "Failed to send verification email: \(error.localizedDescription)"
            )
            throw error
        }
    }

    public func verifyEmail(userId: String, secret: String) async throws {
        logger.info("Verifying email...")

        do {
            _ = try await account.updateVerification(
                userId: userId,
                secret: secret
            )
            logger.info("Email verification completed.")
            await restoreSession()
        } catch {
            logger.error(
                "Email verification failed: \(error.localizedDescription)"
            )
            throw error
        }
    }

    public func changeEmail(
        newEmail: String,
        password: SecureString
    ) async throws {
        logger.info("Updating email address...")

        do {
            _ = try await account.updateEmail(
                email: newEmail,
                password: password.value()
            )
            logger.info("Email address updated.")
            await restoreSession()
        } catch {
            logger.error("Email update failed: \(error.localizedDescription)")
            throw error
        }
    }

    public func changePassword(
        oldPassword: SecureString,
        newPassword: SecureString
    ) async throws {
        logger.info("Updating user password...")

        do {
            _ = try await account.updatePassword(
                password: newPassword.value(),
                oldPassword: oldPassword.value()
            )
            logger.info("Password updated.")
        } catch {
            logger.error("Password update failed: \(error.localizedDescription)")
            throw error
        }
    }

    public func deleteAccount() async throws {
        logger.warning(
            "Account self-deletion is not supported by the Appwrite Apple SDK."
        )
        throw NSError(
            domain: "AuthManager",
            code: 405,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Account deletion is not supported in the client app. Contact support or use the account-management process."
            ]
        )
    }

    public func logout() async {
        isLoading = true
        authError = nil
        logger.info("Logging out of the active session...")

        do {
            _ = try await account.deleteSession(sessionId: "current")
            logger.info("Appwrite session terminated.")
        } catch {
            logger.error(
                "Failed to terminate Appwrite session: \(error.localizedDescription)"
            )
        }

        currentUser = nil
        currentSession = nil
        swiftCodeID = nil
        isAuthenticated = false
        isLoading = false
    }

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

    public func dbUserID(from swiftCodeID: String) -> UUID {
        let cleanID = swiftCodeID
            .replacingOccurrences(of: "sc_id=", with: "")
            .replacingOccurrences(of: "sc_id_", with: "")

        return deterministicUUID(from: cleanID)
    }

    @available(*, deprecated, message: "Remote profile synchronization is not configured.")
    public func syncUserProfile() async {
        guard currentUser != nil, swiftCodeID != nil else {
            logger.debug("Skipping profile sync because no authenticated user is available.")
            return
        }

        logger.info("Using the Appwrite user profile; no external profile sync is configured.")
    }

    private func generateSwiftCodeID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            bytes.count,
            &bytes
        )

        let hexString: String

        if status == errSecSuccess {
            hexString = bytes.map { String(format: "%02X", $0) }.joined()
        } else {
            let fallbackValue = UUID().uuidString
                + "\(ProcessInfo.processInfo.systemUptime)"
            let hash = SHA256.hash(data: Data(fallbackValue.utf8))
            hexString = hash
                .compactMap { String(format: "%02X", $0) }
                .prefix(32)
                .joined()
        }

        return "sc_id=\(hexString)"
    }
}
