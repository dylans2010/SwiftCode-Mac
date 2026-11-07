import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AppwriteOAuthProvider: String, Sendable, Equatable {
    case google
    case github
}

public enum AppwriteOAuthCallback: Sendable, Equatable {
    case success
    case failure(message: String?)
    case recovery(userId: String, secret: String)
    case verification(userId: String, secret: String)
}

public struct AppwriteAccountClient: Sendable {
    public var configuration: AppwriteConfiguration

    private let session: URLSession
    private let secretBox = SessionSecretBox()

    public var onSessionSecretChanged: (@Sendable (String?) -> Void)?

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

    public func createEmailPasswordSession(email: String, password: String) async throws -> AppwriteSession {
        let request = try makeRequest(
            path: "/account/sessions/email", method: "POST",
            jsonBody: ["email": email, "password": password])
        return try await perform(request)
    }

    public func getAccount() async throws -> AppwriteUser {
        guard sessionSecret != nil else { throw AppwriteError.missingSession }
        return try await perform(try makeRequest(path: "/account", method: "GET"))
    }

    public func deleteSession(sessionId: String) async throws {
        try await performEmpty(try makeRequest(
            path: "/account/sessions/\(sessionId)", method: "DELETE"))
        if sessionId == "current" { setSessionSecret(nil) }
    }

    public func createAccount(userId: String, email: String, password: String) async throws -> AppwriteUser {
        let request = try makeRequest(
            path: "/account", method: "POST",
            jsonBody: ["userId": userId, "email": email, "password": password])
        return try await perform(request)
    }

    public func deleteAccount() async throws {
        try await performEmpty(try makeRequest(path: "/account", method: "DELETE"))
        setSessionSecret(nil)
    }

    public func updatePrefs(_ prefs: [String: String]) async throws -> AppwriteUser {
        let request = try makeRequest(
            path: "/account/prefs", method: "PATCH",
            jsonBody: ["prefs": prefs])
        return try await perform(request)
    }

    public func updateEmail(email: String, password: String) async throws -> AppwriteUser {
        let request = try makeRequest(
            path: "/account/email", method: "PATCH",
            jsonBody: ["email": email, "password": password])
        return try await perform(request)
    }

    public func updatePassword(password: String, oldPassword: String) async throws -> AppwriteUser {
        let request = try makeRequest(
            path: "/account/password", method: "PATCH",
            jsonBody: ["password": password, "oldPassword": oldPassword])
        return try await perform(request)
    }

    public func createRecovery(email: String, url: String) async throws {
        let request = try makeRequest(
            path: "/account/recovery", method: "POST",
            jsonBody: ["email": email, "url": url])
        try await performEmpty(request)
    }

    public func updateRecovery(userId: String, secret: String, password: String) async throws {
        let request = try makeRequest(
            path: "/account/recovery", method: "PUT",
            jsonBody: ["userId": userId, "secret": secret, "password": password])
        try await performEmpty(request)
    }

    public func createVerification(url: String) async throws {
        let request = try makeRequest(
            path: "/account/verification", method: "POST",
            jsonBody: ["url": url])
        try await performEmpty(request)
    }

    public func updateVerification(userId: String, secret: String) async throws {
        let request = try makeRequest(
            path: "/account/verification", method: "PUT",
            jsonBody: ["userId": userId, "secret": secret])
        try await performEmpty(request)
    }

    public func ping() async throws -> Bool {
        _ = try await performData(try makeRequest(path: "/ping", method: "GET"))
        return true
    }

    public func listFiles(bucketId: String) async throws -> [AppwriteFile] {
        struct ListResponse: Decodable {
            var files: [AppwriteFile]
        }
        let response: ListResponse = try await perform(try makeRequest(
            path: "/storage/buckets/\(bucketId)/files", method: "GET"))
        return response.files
    }

    public func getFileDownload(bucketId: String, fileId: String) async throws -> Data {
        let (data, _) = try await performData(try makeRequest(
            path: "/storage/buckets/\(bucketId)/files/\(fileId)/download", method: "GET"))
        return data
    }

    public func deleteFile(bucketId: String, fileId: String) async throws {
        try await performEmpty(try makeRequest(
            path: "/storage/buckets/\(bucketId)/files/\(fileId)", method: "DELETE"))
    }

    public func createFile(bucketId: String, fileId: String, data: Data, filename: String, contentType: String) async throws -> AppwriteFile {
        let boundary = "SwiftCode-\(UUID().uuidString)"
        var request = try makeRequest(path: "/storage/buckets/\(bucketId)/files", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartFormData(
            boundary: boundary, fileId: fileId, data: data, filename: filename, contentType: contentType)
        return try await perform(request)
    }

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

    public func parseOAuthCallback(_ url: URL) -> AppwriteOAuthCallback? {
        guard url.scheme == configuration.callbackScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
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

private final class SessionSecretBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
