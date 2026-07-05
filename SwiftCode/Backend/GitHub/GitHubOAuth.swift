import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

@MainActor
final class GitHubOAuth: NSObject, ObservableObject {
    static let shared = GitHubOAuth()
    nonisolated static let clientSecret = EnvironmentValueLoader.value(for: "CLIENT_SECRET", fallback: "missing_client_secret")
    nonisolated static let secretID = EnvironmentValueLoader.value(for: "SECRET_ID", fallback: "missing_secret_id")

    @Published private(set) var isAuthenticating = false
    @Published private(set) var isConnected = false
    @Published private(set) var username: String?
    @Published var errorMessage: String?

    private var authSession: ASWebAuthenticationSession?
    private var pendingState: String?

    private override init() {
        super.init()
        refreshConnectionState()
    }

    func refreshConnectionState() {
        isConnected = GitHubAuth.shared.isAuthenticated

        guard isConnected else {
            username = nil
            return
        }

        Task {
            do {
                let user = try await GitHubAuth.shared.validateToken()
                username = user.login
                isConnected = true
            } catch {
                isConnected = false
                username = nil
            }
        }
    }

    func signInWithGitHub() {
        guard !isAuthenticating else { return }

        guard let config = GitHubOAuthConfig.load() else {
            errorMessage = "GitHub OAuth is not configured. Add GITHUB_CLIENT_ID and CLIENT_SECRET to your environment or .env file."
            return
        }

        guard let authorizationURL = buildAuthorizationURL(config: config) else {
            errorMessage = "Unable to build GitHub authorization request."
            return
        }

        errorMessage = nil
        isAuthenticating = true

        let callbackScheme = URL(string: config.redirectURI)?.scheme
        let session = ASWebAuthenticationSession(url: authorizationURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }

                if let sessionError = error as? ASWebAuthenticationSessionError,
                   sessionError.code == .canceledLogin {
                    self.handleOAuthFailure(.userCancelled)
                    return
                }

                if let error {
                    self.handleOAuthFailure(.network(error.localizedDescription))
                    return
                }

                guard let callbackURL else {
                    self.handleOAuthFailure(.invalidCallback)
                    return
                }

                await self.handleRedirectURL(callbackURL)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        authSession = session

        if !session.start() {
            handleOAuthFailure(.unableToStart)
        }
    }

    func signOut() {
        GitHubAuth.shared.clearToken()
        APIKeyManager.shared.deleteKey(service: .gitHub)
        isAuthenticating = false
        isConnected = false
        username = nil
        pendingState = nil
        errorMessage = nil
    }

    func handleRedirectURL(_ url: URL) async {
        guard let config = GitHubOAuthConfig.load() else {
            handleOAuthFailure(.missingConfiguration)
            return
        }

        await processCallbackURL(url, config: config)
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard let config = GitHubOAuthConfig.load(),
              let expectedURL = URL(string: config.redirectURI),
              url.scheme == expectedURL.scheme,
              url.host == expectedURL.host,
              url.path == expectedURL.path else {
            return false
        }

        Task { @MainActor in
            await self.processCallbackURL(url, config: config)
        }
        return true
    }

    private func buildAuthorizationURL(config: GitHubOAuthConfig) -> URL? {
        let state = Self.randomState()
        pendingState = state

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: "repo workflow read:user"),
            URLQueryItem(name: "state", value: state)
        ]

        return components?.url
    }

    private func processCallbackURL(_ url: URL, config: GitHubOAuthConfig) async {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if let callbackError = items.first(where: { $0.name == "error" })?.value {
            if callbackError == "access_denied" {
                handleOAuthFailure(.userCancelled)
            } else {
                let description = items.first(where: { $0.name == "error_description" })?.value ?? callbackError
                handleOAuthFailure(.invalidResponse(description))
            }
            return
        }

        guard let code = items.first(where: { $0.name == "code" })?.value,
              let state = items.first(where: { $0.name == "state" })?.value else {
            handleOAuthFailure(.invalidCallback)
            return
        }

        guard let pendingStateValue = pendingState, pendingStateValue == state else {
            handleOAuthFailure(.invalidState)
            return
        }

        do {
            let accessToken = try await exchangeCodeForToken(code: code, config: config)
            configureGitHubIntegration(using: accessToken)

            do {
                let user = try await GitHubAuth.shared.validateToken()
                username = user.login
            } catch {
                username = nil
            }

            isConnected = true
            isAuthenticating = false
            errorMessage = nil
            pendingState = nil
        } catch let oauthError as GitHubOAuthError {
            handleOAuthFailure(oauthError)
        } catch {
            handleOAuthFailure(.network(error.localizedDescription))
        }
    }

    private func exchangeCodeForToken(code: String, config: GitHubOAuthConfig) async throws -> String {
        guard let tokenURL = URL(string: "https://github.com/login/oauth/access_token") else {
            throw GitHubOAuthError.invalidResponse("Invalid token endpoint.")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "client_secret", value: config.clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI)
        ]

        var components = URLComponents()
        components.queryItems = bodyItems
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubOAuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(GitHubOAuthTokenResponse.self, from: data)

        if let error = tokenResponse.error {
            throw GitHubOAuthError.invalidResponse(tokenResponse.errorDescription ?? error)
        }

        guard let token = tokenResponse.accessToken,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubOAuthError.tokenExchangeFailed
        }

        return token
    }

    private func configureGitHubIntegration(using token: String) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        GitHubAuth.shared.saveToken(trimmedToken)
        APIKeyManager.shared.storeKey(service: .gitHub, key: trimmedToken)
    }

    private func handleOAuthFailure(_ error: GitHubOAuthError) {
        isAuthenticating = false
        isConnected = GitHubAuth.shared.isAuthenticated
        errorMessage = error.localizedDescription
        pendingState = nil
    }

    private static func randomState() -> String {
        let randomBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let digest = SHA256.hash(data: Data(randomBytes))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

extension GitHubOAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }

        return window
    }
}

private struct GitHubOAuthConfig {
    let clientID: String
    let clientSecret: String
    let redirectURI: String

    static func load() -> GitHubOAuthConfig? {
        let clientID = EnvironmentValueLoader.optionalValue(for: "GITHUB_CLIENT_ID")
        let clientSecret = GitHubOAuth.clientSecret
        let redirectURI = "swiftcode://oauth/callback"

        guard let clientID, !clientID.isEmpty,
              clientSecret != "missing_client_secret" else {
            return nil
        }

        return GitHubOAuthConfig(clientID: clientID, clientSecret: clientSecret, redirectURI: redirectURI)
    }
}

private enum EnvironmentValueLoader {
    private static let dotenv = DotEnvLoader.load(fileName: ".env")

    static func optionalValue(for key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment

        if let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }

        if let raw = dotenv[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }

        return nil
    }

    static func value(for key: String, fallback: String) -> String {
        optionalValue(for: key) ?? fallback
    }
}

private struct DotEnvLoader {
    static func load(fileName: String) -> [String: String] {
        var dictionary: [String: String] = [:]

        let locations: [URL?] = [
            Bundle.main.url(forResource: fileName.replacingOccurrences(of: ".env", with: ""), withExtension: "env"),
            Bundle.main.url(forResource: fileName, withExtension: nil),
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SwiftCode").appendingPathComponent(fileName),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(fileName)
        ]

        for case let fileURL? in locations {
            if let data = try? Data(contentsOf: fileURL),
               let contents = String(data: data, encoding: .utf8) {
                let parsed = parse(contents: contents)
                dictionary.merge(parsed) { (_, new) in new }
            }
        }

        return dictionary
    }

    private static func parse(contents: String) -> [String: String] {
        var dictionary: [String: String] = [:]

        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            let parts = trimmedLine.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                var value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Remove quotes if present
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }

                dictionary[key] = value
            }
        }

        return dictionary
    }
}

private struct GitHubOAuthTokenResponse: Decodable {
    let accessToken: String?
    let scope: String?
    let tokenType: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case scope
        case tokenType = "token_type"
        case error
        case errorDescription = "error_description"
    }
}

private enum GitHubOAuthError: LocalizedError {
    case missingConfiguration
    case unableToStart
    case userCancelled
    case invalidCallback
    case invalidState
    case invalidResponse(String)
    case tokenExchangeFailed
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "GitHub OAuth is not configured."
        case .unableToStart:
            return "Unable to start GitHub authentication."
        case .userCancelled:
            return "Sign in with GitHub was cancelled."
        case .invalidCallback:
            return "Invalid OAuth callback received from GitHub."
        case .invalidState:
            return "OAuth state validation failed. Please try again."
        case .invalidResponse(let message):
            return "GitHub OAuth error: \(message)"
        case .tokenExchangeFailed:
            return "Failed to exchange OAuth code for a token."
        case .network(let message):
            return "Network error during GitHub sign-in: \(message)"
        }
    }
}
