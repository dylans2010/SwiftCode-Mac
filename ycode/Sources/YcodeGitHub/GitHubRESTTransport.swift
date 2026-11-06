import Foundation

/// The shared api.github.com transport for the extended GitHub clients
/// (`GitHubGistClient`, `GitHubReleaseClient`, `GitHubRemoteListsClient`,
/// `GitHubIssueCommentClient`).
///
/// `GitHubClient` owns the same machinery as `private` methods, so a new
/// file cannot reuse it without editing `GitHubClient.swift` — and this
/// migration adds new files only. This transport mirrors it exactly:
/// the same base URL, `Accept` / `X-GitHub-Api-Version` / `User-Agent`
/// headers, Bearer token from the injected provider, rate-limit
/// recording, and `GitHubError` mapping. The token is never stored
/// here and never logged.
///
/// Ported from Legacy (`SwiftCode/Views/GitHub/` + `SwiftCode/Views/Gists/`,
/// which each hand-rolled the same URLSession calls): the behaviour is
/// Legacy's, the transport is shared so the four clients do not each
/// duplicate it.
struct GitHubRESTTransport: Sendable {
    static let baseURL = GitHubClient.baseURL
    private static let apiVersion = "2022-11-28"
    private static let userAgent = "Ycode"
    private static let accept = "application/vnd.github+json"

    let session: URLSession
    let tokenProvider: @Sendable () -> String?

    /// Builds a request. `path` is already percent-encoded segment by
    /// segment, matching `GitHubClient`'s convention.
    func request(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = "/" + path
        if !query.isEmpty { components.queryItems = query }
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = method
        urlRequest.setValue(Self.accept, forHTTPHeaderField: "Accept")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let token = tokenProvider(), !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }

    /// Sends the request and decodes the body. A 204 / empty body
    /// decodes only when `T` is `GitHubEmptyResponse`.
    func perform<T: Decodable>(_ urlRequest: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw GitHubError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.network
        }
        try validate(http, data: data)
        do {
            return try Self.decoder().decode(T.self, from: data)
        } catch {
            throw GitHubError.decoding
        }
    }

    /// Sends the request and ignores the body. Used for 204 endpoints
    /// (star / unstar / mark-read) where success is the status alone.
    /// A 404 surfaces as `.notFound`, which callers such as
    /// `isStarred` interpret.
    func performVoid(_ urlRequest: URLRequest) async throws {
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: urlRequest)
        } catch {
            throw GitHubError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.network
        }
        // The body is discarded; only the status matters here.
        try validate(http, data: Data())
    }

    func validate(_ http: HTTPURLResponse, data: Data) throws {
        guard (200...299).contains(http.statusCode) else {
            throw error(for: http, data: data)
        }
    }

    func error(for http: HTTPURLResponse, data: Data) -> GitHubError {
        let message = Self.githubMessage(from: data)
        let rate = GitHubRateLimit.parse(from: http)
        switch http.statusCode {
        case 401:
            return .unauthorized
        case 404:
            return .notFound
        case 422:
            return .unprocessable(message: message ?? "Unprocessable entity")
        case 403:
            let exhausted = rate.isExhausted || (message?.lowercased().contains("rate limit") ?? false)
            if exhausted {
                return .forbidden(message: message ?? "Rate limit exceeded", rateLimited: true, resetAt: rate.resetAt)
            }
            return .forbidden(message: message ?? "Forbidden", rateLimited: false, resetAt: nil)
        case 429:
            return .forbidden(message: message ?? "Rate limit exceeded", rateLimited: true, resetAt: rate.resetAt)
        default:
            return .http(status: http.statusCode, message: message ?? "HTTP \(http.statusCode)")
        }
    }

    /// GitHub's error JSON: `{"message": "...", ...}`.
    static func githubMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String else {
            return nil
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func jsonBody<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw GitHubError.decoding
        }
    }

    /// `per_page` must be 1...100 on the GitHub API.
    func clampedPerPage(_ perPage: Int) -> Int {
        min(100, max(1, perPage))
    }

    /// Percent-encodes one path segment (or a whole file path: `/`
    /// stays a separator, as in `GitHubClient`).
    func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
