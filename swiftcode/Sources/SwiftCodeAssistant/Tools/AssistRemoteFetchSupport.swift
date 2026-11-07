import Foundation

public enum AssistRemoteFetchError: Error, Sendable, LocalizedError {
    case invalidURL(String)
    case disallowedScheme(String)
    case disallowedHost(String)
    case ssrfBlocked(String)
    case tooManyRedirects
    case redirectToDisallowedHost(String)
    case badStatus(Int, String?)
    case unexpectedContentType(String)
    case responseTooLarge(Int)
    case timeout
    case cancelled
    case rateLimited(resetAt: Date?)
    case decodingFailed(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid URL: \(s)"
        case .disallowedScheme(let s): return "Only HTTPS URLs are allowed (got scheme '\(s)')."
        case .disallowedHost(let h): return "Host '\(h)' is not an approved documentation/API host."
        case .ssrfBlocked(let r): return "Blocked unsafe request target: \(r)"
        case .tooManyRedirects: return "Too many redirects; giving up."
        case .redirectToDisallowedHost(let h): return "Redirect to disallowed host '\(h)' was blocked."
        case .badStatus(let code, let detail):
            return detail.map { "HTTP \($0)" } ?? "HTTP \(code)"
        case .unexpectedContentType(let t): return "Unexpected content type '\(t)'."
        case .responseTooLarge(let cap): return "Response exceeded the \(cap)-byte limit."
        case .timeout: return "Request timed out."
        case .cancelled: return "Request was cancelled."
        case .rateLimited(let reset):
            if let reset { return "Rate limit exhausted; resets at \(reset)." }
            return "Rate limit exhausted."
        case .decodingFailed(let r): return "Failed to decode response: \(r)"
        case .network(let r): return "Network error: \(r)"
        }
    }
}

public enum AssistURLGuard: Sendable {
    public static func isBlockedName(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".localhost") { return true }
        for suffix in [".local", ".internal", ".invalid", ".test", ".example", ".lan", ".home", ".corp"] {
            if h.hasSuffix(suffix) { return true }
        }
        return false
    }

    public static func isIPAddressLiteral(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part), n >= 0, n <= 255 else { return false }
            return true
        }
    }

    public static func validate(_ url: URL, allowedHosts: Set<String>) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw AssistRemoteFetchError.disallowedScheme(url.scheme ?? "(none)")
        }
        guard let host = url.host, !host.isEmpty else {
            throw AssistRemoteFetchError.invalidURL("URL has no host")
        }
        if url.user != nil || url.password != nil {
            throw AssistRemoteFetchError.ssrfBlocked("URL contains embedded credentials")
        }
        if url.port != nil {
            throw AssistRemoteFetchError.ssrfBlocked("explicit port not allowed (got :\(url.port!))")
        }
        if isIPAddressLiteral(host) {
            throw AssistRemoteFetchError.ssrfBlocked("literal IP address '\(host)'")
        }
        if isBlockedName(host) {
            throw AssistRemoteFetchError.ssrfBlocked("private/local hostname '\(host)'")
        }
        let normalized = host.lowercased()
        guard allowedHosts.contains(normalized) else {
            throw AssistRemoteFetchError.disallowedHost(host)
        }
    }
}

public struct AssistFetchOptions: Sendable {
    public var timeout: TimeInterval = 30
    public var maxResponseBytes: Int = 2_000_000
    public var maxRedirects: Int = 5
    public var allowedHosts: Set<String> = []
    public var userAgent: String = "SwiftCode-Assist/1.0 (macOS; +https://developer.apple.com)"
    public var extraHeaders: [String: String] = [:]
    public var acceptedContentTypes: [String] = []
    public var enforceDeclaredLength: Bool = true

    public init() {}
}

public struct AssistHTTPResponse: Sendable {
    public let data: Data
    public let httpResponse: HTTPURLResponse
    public let finalURL: URL

    public var statusCode: Int { httpResponse.statusCode }

    public func header(_ name: String) -> String? {
        httpResponse.value(forHTTPHeaderField: name)
    }

    public var contentType: String? {
        guard let raw = header("Content-Type") else { return nil }
        return raw.split(separator: ";").first.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    public var text: String? {
        String(data: data, encoding: .utf8)
    }
}

public struct AssistRateLimitInfo: Sendable {
    public let limit: Int?
    public let remaining: Int?
    public let resetAt: Date?
    public let retryAfter: TimeInterval?

    public var isExhausted: Bool { remaining == 0 }

    public static func parse(from response: HTTPURLResponse) -> AssistRateLimitInfo {
        func intHeader(_ name: String) -> Int? {
            response.value(forHTTPHeaderField: name).flatMap(Int.init)
        }
        let reset: Date? = intHeader("X-RateLimit-Reset").map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let retry: TimeInterval? = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
        return AssistRateLimitInfo(
            limit: intHeader("X-RateLimit-Limit"),
            remaining: intHeader("X-RateLimit-Remaining"),
            resetAt: reset,
            retryAfter: retry
        )
    }
}

public final class AssistSecureHTTPClient: Sendable {
    public static let shared = AssistSecureHTTPClient()

    private let session: URLSession

    public init(configuration: URLSessionConfiguration? = nil) {
        let config = configuration ?? .ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: config)
    }

    public func get(_ url: URL, options: AssistFetchOptions) async throws -> AssistHTTPResponse {
        try Task.checkCancellation()
        try AssistURLGuard.validate(url, allowedHosts: options.allowedHosts)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = options.timeout
        request.setValue(options.userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in options.extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let delegate = CappedDataDelegate(options: options)
        let session = URLSession(
            configuration: session.configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        let (response, finalURL): (URLResponse, URL)
        do {
            let result = try await session.data(for: request, delegate: delegate)
            response = result.1
            finalURL = delegate.finalURL ?? url
        } catch is CancellationError {
            if let redirectError = delegate.redirectError { throw redirectError }
            throw AssistRemoteFetchError.cancelled
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AssistRemoteFetchError.timeout
        } catch let urlError as URLError where urlError.code == .cancelled {
            if let redirectError = delegate.redirectError { throw redirectError }
            if delegate.sizeExceeded {
                throw AssistRemoteFetchError.responseTooLarge(options.maxResponseBytes)
            }
            throw AssistRemoteFetchError.cancelled
        } catch let fetchError as AssistRemoteFetchError {
            throw fetchError
        } catch {
            throw AssistRemoteFetchError.network(error.localizedDescription)
        }

        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw AssistRemoteFetchError.network("non-HTTP response")
        }
        let data = delegate.body

        if !options.acceptedContentTypes.isEmpty {
            let actual = (http.value(forHTTPHeaderField: "Content-Type") ?? "")
                .split(separator: ";").first.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                } ?? ""
            let ok = options.acceptedContentTypes.contains { actual.hasPrefix($0.lowercased()) }
            if !ok {
                throw AssistRemoteFetchError.unexpectedContentType(actual.isEmpty ? "(none)" : actual)
            }
        }

        let rate = AssistRateLimitInfo.parse(from: http)
        if http.statusCode == 429 || (http.statusCode == 403 && rate.isExhausted) {
            throw AssistRemoteFetchError.rateLimited(resetAt: rate.resetAt)
        }

        guard (200...299).contains(http.statusCode) else {
            var detail: String? = nil
            if let body = String(data: data.prefix(512), encoding: .utf8), !body.isEmpty {
                detail = Self.githubStyleMessage(from: body, status: http.statusCode)
            }
            throw AssistRemoteFetchError.badStatus(http.statusCode, detail)
        }

        return AssistHTTPResponse(data: data, httpResponse: http, finalURL: finalURL)
    }

    private static func githubStyleMessage(from body: String, status: Int) -> String {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? String else {
            return "HTTP \(status)"
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(String(trimmed.prefix(300)))"
    }
}

private final class CappedDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let options: AssistFetchOptions
    private let lock = NSLock()
    private var _body = Data()
    private var _redirectCount = 0
    private var _finalURL: URL?
    private var _sizeExceeded = false
    private var _redirectError: AssistRemoteFetchError?

    var body: Data { lock.withLock { _body } }
    var finalURL: URL? { lock.withLock { _finalURL } }
    var redirectError: AssistRemoteFetchError? { lock.withLock { _redirectError } }
    var sizeExceeded: Bool { lock.withLock { _sizeExceeded } }

    init(options: AssistFetchOptions) {
        self.options = options
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        do {
            guard let target = request.url else {
                throw AssistRemoteFetchError.invalidURL("redirect target missing")
            }
            let count = lock.withLock { () -> Int in _redirectCount += 1; return _redirectCount }
            guard count <= options.maxRedirects else {
                throw AssistRemoteFetchError.tooManyRedirects
            }
            try AssistURLGuard.validate(target, allowedHosts: options.allowedHosts)
            lock.withLock { _finalURL = target }
            completionHandler(request)
        } catch {
            let fetchError = (error as? AssistRemoteFetchError) ?? .network(error.localizedDescription)
            lock.withLock { _redirectError = fetchError }
            completionHandler(nil)
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.withLock { _finalURL = dataTask.currentRequest?.url }
        if options.enforceDeclaredLength,
           let http = response as? HTTPURLResponse,
           let lengthString = http.value(forHTTPHeaderField: "Content-Length"),
           let declared = Int(lengthString),
           declared > options.maxResponseBytes {
            lock.withLock { _sizeExceeded = true }
            dataTask.cancel()
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let exceeded: Bool = lock.withLock {
            _body.append(data)
            if _body.count > options.maxResponseBytes {
                _sizeExceeded = true
                return true
            }
            return false
        }
        if exceeded {
            dataTask.cancel()
        }
    }
}

public actor AssistRemoteResponseCache {
    public struct Entry: Sendable {
        public let data: Data
        public let contentType: String?
        public let finalURL: URL
        public let statusCode: Int
        public let expiresAt: Date
    }

    private var store: [String: Entry] = [:]
    private let maxEntries: Int
    private let defaultTTL: TimeInterval

    public init(maxEntries: Int = 200, defaultTTL: TimeInterval = 600) {
        self.maxEntries = maxEntries
        self.defaultTTL = defaultTTL
    }

    public func get(_ key: String) -> Entry? {
        guard let entry = store[key] else { return nil }
        guard entry.expiresAt > Date() else {
            store.removeValue(forKey: key)
            return nil
        }
        return entry
    }

    public func set(_ key: String, data: Data, contentType: String?, finalURL: URL, statusCode: Int, ttl: TimeInterval? = nil) {
        if store.count >= maxEntries, store[key] == nil {
            if let oldest = store.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                store.removeValue(forKey: oldest)
            }
        }
        store[key] = Entry(
            data: data,
            contentType: contentType,
            finalURL: finalURL,
            statusCode: statusCode,
            expiresAt: Date().addingTimeInterval(ttl ?? defaultTTL)
        )
    }

    public func removeAll() {
        store.removeAll()
    }
}

public enum AssistJSON: Sendable {
    public static func parse(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw AssistRemoteFetchError.decodingFailed("invalid JSON")
        }
    }

    public static func object(_ value: Any) -> [String: Any]? {
        value as? [String: Any]
    }

    public static func array(_ value: Any) -> [Any]? {
        value as? [Any]
    }

    public static func richText(_ value: Any?) -> String {
        guard let spans = value as? [[String: Any]] else {
            if let s = value as? String { return s }
            return ""
        }
        return spans.compactMap { $0["text"] as? String }.joined()
    }
}

public enum AssistInputNumbers: Sendable {
    public static func integer(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double, d == d.rounded(), d <= Double(Int.max), d >= Double(Int.min) { return Int(d) }
        if let s = value as? String, let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return i }
        return nil
    }

    public static func boolean(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let s = value as? String {
            switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }
}
