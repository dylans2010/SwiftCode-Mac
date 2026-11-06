import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The OAuth providers Legacy offered (`AuthManager.loginWithGoogle`,
/// `loginWithGitHub`).
public enum AppwriteOAuthProvider: String, Sendable, Equatable {
    case google
    case github
}

/// What an Appwrite callback URL means, once parsed by
/// `AppwriteAccountClient.parseOAuthCallback(_:)`.
public enum AppwriteOAuthCallback: Sendable, Equatable {
    /// The provider flow finished and the browser was sent back to the
    /// app's success URL.
    case success
    /// The provider flow, or Appwrite, rejected the sign-in.
    case failure(message: String?)
    /// A password-recovery link: complete it with
    /// `updateRecovery(userId:secret:password:)`.
    case recovery(userId: String, secret: String)
    /// An email-verification link: complete it with
    /// `updateVerification(userId:secret:)`.
    case verification(userId: String, secret: String)
}

/// The Appwrite Account API over plain `URLSession`, following the
/// SwiftCodeGitHub precedent (`GitHubClient`): a value type with no
/// stored secret — the session secret is read from a locked box on
/// every request, and the host persists it through
/// `onSessionSecretChanged` (wired to the secret store by
/// `CloudAuthManager`).
///
/// Endpoints covered are exactly the ones Legacy's `AuthManager`
/// used through the Appwrite SDK, plus `DELETE /account` (which the
/// SDK could not do — Legacy's `deleteAccount` always threw — but
/// the REST API supports) and `GET /ping` (Legacy's
/// `CloudManagementView` server test). Appwrite Storage file
/// operations are included because they fall out of the same request
/// machinery and `BackupEngine` needs them (`listObjects`,
/// `download`, `delete`, and `multipart/form-data` upload via
/// `createFile` on the `backups` bucket).
///
/// Authentication is cookie-based, as in the SDK: creating a
/// session makes Appwrite set `a_session_<project>`; the client
/// captures that cookie's value from the `Set-Cookie` response
/// header, keeps it in the locked box, and sends it back as a
/// `Cookie` header. The secret is never logged and never written to
/// a file by this client.
public struct AppwriteAccountClient: Sendable {
    public var configuration: AppwriteConfiguration

    private let session: URLSession
    private let secretBox = SessionSecretBox()

    /// Called whenever the session secret is set (sign-in) or cleared
    /// (sign-out), so the host can persist it. The client itself never
    /// touches the keychain.
    public var onSessionSecretChanged: (@Sendable (String?) -> Void)?

    /// The captured session secret, if a session is active. Set from
    /// the `Set-Cookie` header of a session-creation response, or by
    /// the host from the secret store at startup.
    public var sessionSecret: String? {
        get { secretBox.value }
        nonmutating set { setSessionSecret(newValue) }
    }

    public init(
        configuration: AppwriteConfiguration = AppwriteConfiguration(),
        session: URLSession = .shared,
        initialSessionSecret: String? = nil
    ) {
        self.configuration = configuration
        self.session = session
        secretBox.value = initialSessionSecret
    }

    private func setSessionSecret(_ secret: String?) {
        let changed = secretBox.value != secret
        secretBox.value = secret
        if changed { onSessionSecretChanged?(secret) }
    }

    // MARK: - Request building

    /// Builds a request for `path` below the endpoint (leading `/`
    /// optional). Every request carries `X-Appwrite-Project`;
    /// authenticated requests also carry the session cookie. Exposed
    /// for tests (via `@testable`) so request shape is asserted
    /// without any network.
    func makeRequest(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil
    ) throws -> URLRequest {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(
            url: configuration.endpoint.appendingPathComponent(cleanPath),
            resolvingAgainstBaseURL: false
        ) else {
            throw AppwriteError.invalidConfiguration("Cannot build a URL for \(path)")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw AppwriteError.invalidConfiguration("Cannot build a URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.projectID, forHTTPHeaderField: "X-Appwrite-Project")
        request.setValue("SwiftCode", forHTTPHeaderField: "User-Agent")
        if let secret = sessionSecret, !secret.isEmpty {
            request.setValue(
                "\(configuration.sessionCookieName)=\(secret)",
                forHTTPHeaderField: "Cookie")
        }
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        return request
    }

    // MARK: - Transport

    private struct EmptyResponse: Decodable {}

    private func performData(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppwriteError.network(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppwriteError.network("The server returned a response that was not HTTP.")
        }
        captureSessionCookie(from: httpResponse)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw errorFromBody(data, status: httpResponse.statusCode)
        }
        return (data, httpResponse)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await performData(request)
        do {
            return try AppwriteDecoder.decoder().decode(T.self, from: data)
        } catch {
            throw AppwriteError.decoding(error.localizedDescription)
        }
    }

    private func performEmpty(_ request: URLRequest) async throws {
        let (data, _) = try await performData(request)
        if data.isEmpty { return }
        // Appwrite answers deletions with `{}`; accept it, and any
        // other decodable empty object, without failing.
        _ = try? AppwriteDecoder.decoder().decode(EmptyResponse.self, from: data)
    }

    private func errorFromBody(_ data: Data, status: Int) -> AppwriteError {
        if let body = try? JSONDecoder().decode(AppwriteErrorBody.self, from: data) {
            return .http(status: status, code: body.code, type: body.type, message: body.message)
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .http(status: status, code: nil, type: nil,
                     message: (text?.isEmpty == false ? text! : "The server returned status \(status)."))
    }

    /// Captures the session secret from a `Set-Cookie` header, when
    /// the response sets the `a_session_<project>` cookie.
    private func captureSessionCookie(from response: HTTPURLResponse) {
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, name.lowercased() == "set-cookie",
                  let cookie = value as? String else { continue }
            let firstPart = cookie.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            let pair = firstPart.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2, pair[0] == configuration.sessionCookieName, !pair[1].isEmpty {
                setSessionSecret(pair[1])
            }
        }
    }

    // MARK: - Sessions and account

    /// `POST /account/sessions/email`: signs in with email and
    /// password. On success the session secret is captured from the
    /// response cookie (see the type documentation).
    public func createEmailPasswordSession(email: String, password: String) async throws -> AppwriteSession {
        let request = try makeRequest(
            path: "/account/sessions/email", method: "POST",
            jsonBody: ["email": email, "password": password])
        return try await perform(request)
    }

    /// `GET /account`: the signed-in user. Throws `.missingSession`
    /// without a network call when no session secret is held.
    public func getAccount() async throws -> AppwriteUser {
        guard sessionSecret != nil else { throw AppwriteError.missingSession }
        return try await perform(try makeRequest(path: "/account", method: "GET"))
    }

    /// `DELETE /account/sessions/{sessionId}`. Pass `"current"` to end
    /// this session. Clears the stored secret on success.
    public func deleteSession(sessionId: String) async throws {
        try await performEmpty(try makeRequest(
            path: "/account/sessions/\(sessionId)", method: "DELETE"))
        if sessionId == "current" { setSessionSecret(nil) }
    }

    /// `POST /account`: creates an account. Pass `"unique()"` as the
    /// user id and Appwrite generates one, as Legacy did
    /// (`account.create(userId: ID.unique(), ...)`).
    public func createAccount(userId: String, email: String, password: String) async throws -> AppwriteUser {
        let request = try makeRequest(
            path: "/account", method: "POST",
            jsonBody: ["userId": userId, "email": email, "password": password])
        return try await perform(request)
    }

    /// `DELETE /account`: deletes the signed-in account. Legacy's
    /// `AuthManager.deleteAccount` always threw (the Apple SDK does
    /// not expose self-deletion); the REST API does support it, so
    /// this client implements it for real. Clears the stored secret
    /// on success.
    public func deleteAccount() async throws {
        try await performEmpty(try makeRequest(path: "/account", method: "DELETE"))
        setSessionSecret(nil)
    }

    /// `PATCH /account/prefs`: replaces the signed-in user's
    /// preferences object. Legacy used this to store `swiftcode_id`.
    public func updatePrefs(_ prefs: [String: String]) async throws -> AppwriteUser {
        let request = try makeRequest(
            path: "/account/prefs", method: "PATCH",
            jsonBody: ["prefs": prefs])
        return try await perform(request)
    }

    /// `PATCH /account/email`: changes the signed-in user's email.
    public func updateEmail(email: String, password: String) async throws -> AppwriteUser {
        let request = try makeRequest(
            path: "/account/email", method: "PATCH",
            jsonBody: ["email": email, "password": password])
        return try await perform(request)
    }

    /// `PATCH /account/password`: changes the signed-in user's
    /// password. The old password is required.
    public func updatePassword(password: String, oldPassword: String) async throws -> AppwriteUser {
        let request = try makeRequest(
            path: "/account/password", method: "PATCH",
            jsonBody: ["password": password, "oldPassword": oldPassword])
        return try await perform(request)
    }

    // MARK: - Password recovery

    /// `POST /account/recovery`: sends the password-reset email.
    /// `url` is the link the email points at — Legacy used the
    /// `appwrite-callback-<project>://reset-password` URL.
    public func createRecovery(email: String, url: String) async throws {
        let request = try makeRequest(
            path: "/account/recovery", method: "POST",
            jsonBody: ["email": email, "url": url])
        try await performEmpty(request)
    }

    /// `PUT /account/recovery`: completes a password reset with the
    /// `userId` and `secret` from the emailed link.
    public func updateRecovery(userId: String, secret: String, password: String) async throws {
        let request = try makeRequest(
            path: "/account/recovery", method: "PUT",
            jsonBody: ["userId": userId, "secret": secret, "password": password])
        try await performEmpty(request)
    }

    // MARK: - Email verification

    /// `POST /account/verification`: sends the verification email.
    /// `url` is the link the email points at — Legacy used the
    /// `appwrite-callback-<project>://verify` URL.
    public func createVerification(url: String) async throws {
        let request = try makeRequest(
            path: "/account/verification", method: "POST",
            jsonBody: ["url": url])
        try await performEmpty(request)
    }

    /// `PUT /account/verification`: completes email verification with
    /// the `userId` and `secret` from the emailed link.
    public func updateVerification(userId: String, secret: String) async throws {
        let request = try makeRequest(
            path: "/account/verification", method: "PUT",
            jsonBody: ["userId": userId, "secret": secret])
        try await performEmpty(request)
    }

    // MARK: - Server ping

    /// `GET /ping`: Legacy's `CloudManagementView` server test
    /// (`account.client.ping()`). Returns true on any 2xx answer.
    public func ping() async throws -> Bool {
        _ = try await performData(try makeRequest(path: "/ping", method: "GET"))
        return true
    }

    // MARK: - Storage (Appwrite Storage REST)

    /// `GET /storage/buckets/{bucketId}/files`: the files in a
    /// bucket. This is what `BackupEngine.fetchCloudBackups` needs
    /// (`cloudProvider.storage.listObjects(bucket: "backups", ...)`).
    public func listFiles(bucketId: String) async throws -> [AppwriteFile] {
        struct ListResponse: Decodable {
            var files: [AppwriteFile]
        }
        let response: ListResponse = try await perform(try makeRequest(
            path: "/storage/buckets/\(bucketId)/files", method: "GET"))
        return response.files
    }

    /// `GET /storage/buckets/{bucketId}/files/{fileId}/download`:
    /// the file's bytes. What `BackupEngine.restore` needs.
    public func getFileDownload(bucketId: String, fileId: String) async throws -> Data {
        let (data, _) = try await performData(try makeRequest(
            path: "/storage/buckets/\(bucketId)/files/\(fileId)/download", method: "GET"))
        return data
    }

    /// `DELETE /storage/buckets/{bucketId}/files/{fileId}`. What
    /// `BackupEngine.delete` needs.
    public func deleteFile(bucketId: String, fileId: String) async throws {
        try await performEmpty(try makeRequest(
            path: "/storage/buckets/\(bucketId)/files/\(fileId)", method: "DELETE"))
    }

    /// `POST /storage/buckets/{bucketId}/files`: creates a file with a
    /// `multipart/form-data` upload (the `fileId` field plus the `file`
    /// part carrying the bytes). What `BackupEngine.performBackup`
    /// needs. Returns the created file, whose `id` is the file id
    /// within the bucket.
    public func createFile(bucketId: String, fileId: String, data: Data, filename: String, contentType: String) async throws -> AppwriteFile {
        let boundary = "SwiftCode-\(UUID().uuidString)"
        var request = try makeRequest(path: "/storage/buckets/\(bucketId)/files", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartFormData(
            boundary: boundary, fileId: fileId, data: data, filename: filename, contentType: contentType)
        return try await perform(request)
    }

    /// Builds the `multipart/form-data` body for a Storage file
    /// creation: the `fileId` text field, then the `file` part with
    /// the filename and content type, then the raw bytes. Exposed
    /// for tests (via `@testable`) so the body shape is asserted
    /// without any network.
    static func multipartFormData(boundary: String, fileId: String, data: Data, filename: String, contentType: String) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"fileId\"\r\n\r\n")
        append("\(fileId)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    // MARK: - OAuth2

    /// The browser URL that starts an OAuth2 sign-in for `provider`,
    /// i.e. `{endpoint}/account/sessions/oauth2/{provider}` with the
    /// project id and the success/failure redirect URLs. This is the
    /// URL the Appwrite SDK opens in its web-auth session; Legacy
    /// passed the `appwrite-callback-<project>://` scheme as both
    /// success and failure URLs.
    public func oauthAuthorizeURL(
        provider: AppwriteOAuthProvider,
        success: String? = nil,
        failure: String? = nil
    ) -> URL? {
        let callback = "\(configuration.callbackScheme)://"
        var components = URLComponents(
            url: configuration.endpoint
                .appendingPathComponent("account/sessions/oauth2/\(provider.rawValue)"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "project", value: configuration.projectID),
            URLQueryItem(name: "success", value: success ?? callback),
            URLQueryItem(name: "failure", value: failure ?? callback),
        ]
        return components?.url
    }

    /// Parses a URL the app was opened with on the
    /// `appwrite-callback-<project>` scheme. Recovery and
    /// verification links carry `userId` and `secret` query items;
    /// anything else on the scheme is a finished (or failed) OAuth
    /// flow. Returns nil when the URL is not for this client at all.
    public func parseOAuthCallback(_ url: URL) -> AppwriteOAuthCallback? {
        guard url.scheme == configuration.callbackScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        // Appwrite reports a failed OAuth flow by redirecting to the
        // failure URL with an error.
        if let error = query["error"], !error.isEmpty {
            return .failure(message: query["error_description"] ?? error)
        }
        let path = components.host ?? ""
        if let userId = query["userId"], let secret = query["secret"],
           !userId.isEmpty, !secret.isEmpty {
            switch path {
            case "reset-password": return .recovery(userId: userId, secret: secret)
            case "verify": return .verification(userId: userId, secret: secret)
            default: break
            }
        }
        return .success
    }
}

/// The locked box holding the session secret, following the
/// `RateLimitBox` precedent in `SwiftCodeGitHub`: a struct's stored
/// secret needs a reference box so non-mutating async methods can
/// read and update it.
private final class SessionSecretBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
