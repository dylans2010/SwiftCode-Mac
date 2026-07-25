import Foundation
import Observation
import os.log

@Observable
@MainActor
public final class SupabaseAuthService: AuthenticationProvider, @unchecked Sendable {
    public static let shared = SupabaseAuthService()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "SupabaseAuth")

    // State properties observed by SwiftUI
    public var authState: CloudAuthState = .unauthenticated
    public var currentUserEmail: String? = nil
    public var currentUserID: String? = nil
    public var accessToken: String? = nil
    public var refreshToken: String? = nil
    public var expiresAt: Date? = nil

    // Endpoint details (loaded from settings/defaults)
    public var supabaseURL: String {
        get {
            UserDefaults.standard.string(forKey: "com.swiftcode.supabase.url") ?? "https://api.supabase.co/v1"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "com.swiftcode.supabase.url")
        }
    }

    public var supabaseAnonKey: String {
        get {
            KeychainService.shared.get(forKey: "com.swiftcode.supabase.anon_key") ?? ""
        }
        set {
            KeychainService.shared.set(newValue, forKey: "com.swiftcode.supabase.anon_key")
        }
    }

    private let urlSession: URLSession = URLSession(configuration: .default)

    private init() {
        loadSessionFromKeychain()
        // Trigger non-blocking automatic token refresh on startup if authenticated
        if authState == .authenticated {
            Task {
                try? await refreshSession()
            }
        }
    }

    private func loadSessionFromKeychain() {
        if let email = UserDefaults.standard.string(forKey: "com.swiftcode.cloud.auth.email"),
           let userID = UserDefaults.standard.string(forKey: "com.swiftcode.cloud.auth.userid"),
           let token = KeychainService.shared.get(forKey: "com.swiftcode.cloud.auth.token") {
            self.currentUserEmail = email
            self.currentUserID = userID
            self.accessToken = token
            self.refreshToken = KeychainService.shared.get(forKey: "com.swiftcode.cloud.auth.refresh_token")
            self.expiresAt = UserDefaults.standard.object(forKey: "com.swiftcode.cloud.auth.expires_at") as? Date
            self.authState = .authenticated
            logger.info("Session loaded successfully for user: \(email, privacy: .public)")
        } else {
            self.authState = .unauthenticated
        }
    }

    private func saveSession(email: String, userID: String, token: String, refresh: String?, expires: Date?) {
        self.currentUserEmail = email
        self.currentUserID = userID
        self.accessToken = token
        self.refreshToken = refresh
        self.expiresAt = expires
        self.authState = .authenticated

        UserDefaults.standard.set(email, forKey: "com.swiftcode.cloud.auth.email")
        UserDefaults.standard.set(userID, forKey: "com.swiftcode.cloud.auth.userid")
        UserDefaults.standard.set(expires, forKey: "com.swiftcode.cloud.auth.expires_at")
        KeychainService.shared.set(token, forKey: "com.swiftcode.cloud.auth.token")
        if let refresh {
            KeychainService.shared.set(refresh, forKey: "com.swiftcode.cloud.auth.refresh_token")
        }
        logger.info("Session saved successfully for user: \(email, privacy: .public)")
    }

    private func clearSession() {
        self.currentUserEmail = nil
        self.currentUserID = nil
        self.accessToken = nil
        self.refreshToken = nil
        self.expiresAt = nil
        self.authState = .unauthenticated

        UserDefaults.standard.removeObject(forKey: "com.swiftcode.cloud.auth.email")
        UserDefaults.standard.removeObject(forKey: "com.swiftcode.cloud.auth.userid")
        UserDefaults.standard.removeObject(forKey: "com.swiftcode.cloud.auth.expires_at")
        KeychainService.shared.delete(forKey: "com.swiftcode.cloud.auth.token")
        KeychainService.shared.delete(forKey: "com.swiftcode.cloud.auth.refresh_token")
        logger.info("Session cleared successfully.")
    }

    // MARK: - Authentication API

    public func signInWithEmail(email: String, password: String) async throws {
        self.authState = .authenticating
        logger.info("Initiating email sign-in...")

        let endpoint = "\(supabaseURL)/auth/v1/token?grant_type=password"
        guard let url = URL(string: endpoint) else {
            self.authState = .error
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                self.authState = .error
                throw URLError(.badServerResponse)
            }

            guard httpResponse.statusCode == 200 else {
                self.authState = .error
                let errorMsg = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data).errorDescription
                throw NSError(domain: "SupabaseAuth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg ?? "Invalid email or password"])
            }

            let tokenResponse = try JSONDecoder().decode(SupabaseTokenResponse.self, from: data)
            let expiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

            saveSession(
                email: tokenResponse.user.email,
                userID: tokenResponse.user.id,
                token: tokenResponse.accessToken,
                refresh: tokenResponse.refreshToken,
                expires: expiryDate
            )
        } catch {
            self.authState = .error
            logger.error("Email sign-in failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func signUpWithEmail(email: String, password: String) async throws {
        self.authState = .authenticating
        logger.info("Initiating email sign-up...")

        let endpoint = "\(supabaseURL)/auth/v1/signup"
        guard let url = URL(string: endpoint) else {
            self.authState = .error
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                self.authState = .error
                throw URLError(.badServerResponse)
            }

            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                self.authState = .error
                let errorMsg = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data).errorDescription
                throw NSError(domain: "SupabaseAuth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg ?? "Account creation failed"])
            }

            let tokenResponse = try JSONDecoder().decode(SupabaseTokenResponse.self, from: data)
            let expiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

            saveSession(
                email: tokenResponse.user.email,
                userID: tokenResponse.user.id,
                token: tokenResponse.accessToken,
                refresh: tokenResponse.refreshToken,
                expires: expiryDate
            )
        } catch {
            self.authState = .error
            logger.error("Email sign-up failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func signInWithProvider(name: String) async throws {
        self.authState = .authenticating
        logger.info("Initiating OAuth flow for provider: \(name, privacy: .public)")

        // Configured redirect URI: swiftcode://oauth-check
        let redirectURI = "swiftcode://oauth-check"
        let endpoint = "\(supabaseURL)/auth/v1/authorize?provider=\(name.lowercased())&redirect_to=\(redirectURI)"

        guard let url = URL(string: endpoint) else {
            self.authState = .error
            throw URLError(.badURL)
        }

        // Open external browser or web view for production login
        if NSWorkspace.shared.open(url) {
            logger.info("OAuth browser session opened successfully.")
        } else {
            self.authState = .error
            throw NSError(domain: "SupabaseAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to open login web page"])
        }
    }

    public func signInAnonymously() async throws {
        self.authState = .authenticating
        logger.info("Initiating anonymous session...")

        let guestEmail = "anonymous_guest_\(UUID().uuidString.prefix(8))@swiftcode.com"
        let guestPassword = UUID().uuidString

        // Guest accounts use standard credentials internally to allow standard DB actions and RLS policies
        try await signUpWithEmail(email: guestEmail, password: guestPassword)
        // Store guest indicator
        UserDefaults.standard.set(true, forKey: "com.swiftcode.cloud.auth.is_guest")
    }

    public func migrateGuestToEmail(email: String, password: String) async throws {
        logger.info("Migrating guest account to production credentials...")
        // Securely transition anonymous user metadata to real credentials
        guard let token = accessToken else {
            throw NSError(domain: "SupabaseAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated to migrate profile"])
        }

        let endpoint = "\(supabaseURL)/auth/v1/user"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data).errorDescription
            throw NSError(domain: "SupabaseAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: errorMsg ?? "Failed to update credentials"])
        }

        UserDefaults.standard.set(false, forKey: "com.swiftcode.cloud.auth.is_guest")
        try await signInWithEmail(email: email, password: password)
    }

    public func resetPassword(email: String) async throws {
        logger.info("Sending password reset link...")

        let endpoint = "\(supabaseURL)/auth/v1/recover"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["email": email]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data).errorDescription
            throw NSError(domain: "SupabaseAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: errorMsg ?? "Password recovery request failed"])
        }
    }

    public func signOut() async throws {
        logger.info("Signing out...")
        guard let token = accessToken else {
            clearSession()
            return
        }

        let endpoint = "\(supabaseURL)/auth/v1/logout"
        if let url = URL(string: endpoint) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            _ = try? await urlSession.data(for: request)
        }

        clearSession()
    }

    public func deleteAccount() async throws {
        logger.info("Deleting user account...")
        guard let token = accessToken else { return }

        // Deletes the active user profile, cascades down database dependencies, and signs out
        let endpoint = "\(supabaseURL)/auth/v1/user"
        if let url = URL(string: endpoint) {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            _ = try? await urlSession.data(for: request)
        }

        clearSession()
    }

    public func refreshSession() async throws {
        guard let refresh = refreshToken else { return }
        logger.info("Refreshing user session...")

        let endpoint = "\(supabaseURL)/auth/v1/token?grant_type=refresh_token"
        guard let url = URL(string: endpoint) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["refresh_token": refresh]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

            let tokenResponse = try JSONDecoder().decode(SupabaseTokenResponse.self, from: data)
            let expiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

            saveSession(
                email: tokenResponse.user.email,
                userID: tokenResponse.user.id,
                token: tokenResponse.accessToken,
                refresh: tokenResponse.refreshToken,
                expires: expiryDate
            )
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

// MARK: - API Codable Payloads

private struct SupabaseTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
    }
}

private struct SupabaseUser: Codable {
    let id: String
    let email: String
}

private struct SupabaseErrorResponse: Codable {
    let msg: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case msg
        case errorDescription = "error_description"
    }
}
