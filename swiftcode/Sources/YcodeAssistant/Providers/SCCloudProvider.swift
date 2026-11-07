import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SCCloudProvider: AssistantProvider {
    public let kind = ProviderKind.scCloud

    public var baseURL: String
    public var fingerprint: String?

    public static let fingerprintHeaderName = "X-SwiftCode-Device-Fingerprint"
    public static let dailyRequestLimit = 10
    public static let rateLimitWindow: TimeInterval = 24 * 60 * 60
    public static let requestTimeout: TimeInterval = 180

    public static let unconfiguredHint =
        "SwiftCode Cloud is not configured. Enter a real SCCloud endpoint URL in Settings ▸ Coding Assistant — " +
        "no default endpoint is shipped. The device identity used for fair-use metering is generated automatically."

    private let cache: SCCloudModelCache
    private let limiter: SCCloudRateLimiter

    public init(baseURL: String = "", fingerprint: String? = nil,
                cache: SCCloudModelCache = SCCloudModelCache(), limiter: SCCloudRateLimiter = .shared) {
        self.baseURL = baseURL
        self.fingerprint = fingerprint
        self.cache = cache
        self.limiter = limiter
    }

    public var isConfigured: Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let host = url.host, !host.isEmpty else { return false }
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return host == "127.0.0.1" || host == "localhost" || host == "::1"
        default: return false
        }
    }

    public func availability() async -> ProviderAvailability {
        guard isConfigured else { return .signedOut(hint: Self.unconfiguredHint) }
        do {
            let models = try await listModels()
            return models.isEmpty ? .noModels(hint: "SwiftCode Cloud lists no models at \(baseURL).") : .ready(models)
        } catch let e as AssistantError {
            switch e {
            case .notSignedIn(let hint): return .signedOut(hint: hint)
            case .unreachable(_, _, let hint): return .notRunning(hint: hint)
            default: return .failed(e.errorDescription ?? "\(e)")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func listModels() async throws -> [ModelInfo] {
        if let cached = cache.modelsIfFresh(for: baseURL) { return cached }
        guard isConfigured, let url = HTTP.url(baseURL, "v1/models") else {
            throw AssistantError.notSignedIn(hint: Self.unconfiguredHint)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let fingerprint, !fingerprint.isEmpty {
            request.setValue(fingerprint, forHTTPHeaderField: Self.fingerprintHeaderName)
        }
        let response: HTTP.Response
        do {
            response = try await HTTP.send(request, timeout: 30)
        } catch {
            if let cached = cache.modelsIfAny(for: baseURL) { return cached }
            if HTTP.isUnreachable(error) {
                throw AssistantError.unreachable(service: "SwiftCode Cloud", url: baseURL,
                                                 hint: "Check the network connection and that the SCCloud endpoint is running.")
            }
            throw error
        }
        guard response.status == 200 else {
            if let cached = cache.modelsIfAny(for: baseURL) { return cached }
            throw Self.mapHTTPError(status: response.status, body: response.body)
        }
        let models = Self.parseModels(response.body)
        cache.store(models, for: baseURL)
        return models
    }

    public func contextWindow(model: String) async -> Int? {
        cache.modelsIfFresh(for: baseURL)?.first { $0.id == model }?.contextWindow
    }

    public func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let provider = self
        return eventStream { out in
            guard provider.isConfigured, let url = HTTP.url(provider.baseURL, "v1/chat/completions") else {
                throw AssistantError.notSignedIn(hint: Self.unconfiguredHint)
            }
            guard let fingerprint = provider.fingerprint, !fingerprint.isEmpty else {
                throw AssistantError.failed("SwiftCode Cloud has no device identity yet. Toggle the cloud model off and on again in Settings ▸ Coding Assistant.")
            }
            let gate = provider.limiter.checkGate()
            guard gate.allowed else {
                throw AssistantError.usageLimit("Daily limit reached — SwiftCode Cloud allows \(Self.dailyRequestLimit) requests per day per device for fair use." +
                    (gate.retryAfter.map { " Try again in \(SCCloudRateLimiter.formatDuration($0))." } ?? " Try again in 24 hours."))
            }

            let model = try await provider.resolveModel(request.model)
            var messages: [[String: String]] = [["role": "system", "content": request.instructions]]
            messages += request.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
            var body: [String: Any] = ["model": model, "messages": messages, "stream": false]
            let g = request.generation
            if let n = g.maxOutputTokens { body["max_tokens"] = n }
            if let t = g.temperature { body["temperature"] = t }
            if let p = g.topP { body["top_p"] = p }

            var httpRequest = URLRequest(url: url)
            httpRequest.httpMethod = "POST"
            httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            httpRequest.setValue(fingerprint, forHTTPHeaderField: Self.fingerprintHeaderName)
            httpRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

            let response: HTTP.Response
            do {
                response = try await HTTP.send(httpRequest, timeout: Self.requestTimeout)
            } catch where HTTP.isUnreachable(error) {
                throw AssistantError.unreachable(service: "SwiftCode Cloud", url: provider.baseURL,
                                                 hint: "Check the network connection and that the SCCloud endpoint is running.")
            }
            provider.limiter.recordRequest()

            switch response.status {
            case 200..<300:
                let text = try Self.parseResponse(response.body)
                if !text.isEmpty { out.yield(.text(text)) }
                out.yield(.finished(nil))
            case 429:
                throw AssistantError.usageLimit("SwiftCode Cloud reported its rate limit. Try again later.")
            default:
                throw Self.mapHTTPError(status: response.status, body: response.body)
            }
        }
    }

    func resolveModel(_ explicit: String?) async throws -> String {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.endpointName(forInternalID: explicit) ?? explicit
        }
        let models = try await listModels()
        guard let first = models.first else {
            throw AssistantError.failed("SwiftCode Cloud lists no models. Open Settings ▸ Coding Assistant and refresh the model list, then try again.")
        }
        return first.id
    }

    static func parseModels(_ body: Data) -> [ModelInfo] {
        guard let o = JSON.object(body), let list = o["data"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return list.compactMap { item -> ModelInfo? in
            guard let rawID = item["id"] as? String else { return nil }
            let id = canonicalModelName(rawID)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return ModelInfo(id: id, displayName: id, contextWindow: JSON.int(item["context_window"]))
        }.sorted { $0.id < $1.id }
    }

    static func canonicalModelName(_ discoveredID: String) -> String {
        let trimmed = discoveredID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(":latest") { return String(trimmed.dropLast(":latest".count)) }
        return trimmed
    }

    static func endpointName(forInternalID id: String) -> String? {
        guard id == internalIDPrefix || id.hasPrefix(internalIDPrefix + ":") else { return nil }
        guard id != internalIDPrefix else { return nil }
        return canonicalModelName(String(id.dropFirst(internalIDPrefix.count + 1)))
    }

    static func isCloudModelID(_ id: String) -> Bool {
        id == internalIDPrefix || id.hasPrefix(internalIDPrefix + ":")
    }

    static let internalIDPrefix = "swiftcode-cloud"

    static let displayNameFallback = "SwiftCode Cloud Model"

    static func parseResponse(_ data: Data) throws -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            for key in ["response", "output", "text", "content", "result", "answer"] {
                if let text = json[key] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
            throw AssistantError.malformed("The SwiftCode Cloud endpoint returned a response that could not be understood.")
        }
        if let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        throw AssistantError.malformed("The SwiftCode Cloud endpoint returned a response that could not be understood.")
    }

    static func mapHTTPError(status: Int, body: Data) -> AssistantError {
        let (message, _) = HTTP.errorMessage(body)
        let raw = String(decoding: body.prefix(8000), as: UTF8.self)
        if status == 530 || raw.contains("Cloudflare Tunnel error") || raw.contains("1033") || raw.contains("<!doctype html>") || raw.contains("<html") {
            return .temporarilyUnavailable("The SwiftCode Cloud model server is currently offline or unreachable (tunnel error). Please try again later or select another model in Settings ▸ Coding Assistant.")
        }
        if status == 401 {
            return .notSignedIn(hint: "The SCCloud endpoint rejected this device's identity. Toggle the cloud model off and on again in Settings ▸ Coding Assistant.")
        }
        let preview = message.count > 300 ? String(message.prefix(300)) + "…" : message
        return .http(status: status, message: preview.isEmpty ? "The SCCloud endpoint returned an error." : preview)
    }

    public static func provisionFingerprint() -> String {
        "ssc_" + SHA256.hash(SecureRandom.bytes(32)).map { String(format: "%02x", $0) }.joined()
    }
}

public final class SCCloudModelCache: @unchecked Sendable {
    public static let cacheTTL: TimeInterval = 60 * 60

    private let lock = NSLock()
    private var models: [ModelInfo]?
    private var updatedAt: Date?
    private var endpointURL: String?

    public init() {}

    func modelsIfFresh(for endpoint: String) -> [ModelInfo]? {
        lock.lock()
        defer { lock.unlock() }
        guard endpointURL == endpoint, let models, let updatedAt,
              Date().timeIntervalSince(updatedAt) <= Self.cacheTTL else { return nil }
        return models
    }

    func modelsIfAny(for endpoint: String) -> [ModelInfo]? {
        lock.lock()
        defer { lock.unlock() }
        guard endpointURL == endpoint else { return nil }
        return models
    }

    func store(_ models: [ModelInfo], for endpoint: String) {
        lock.lock()
        self.models = models
        self.updatedAt = Date()
        self.endpointURL = endpoint
        lock.unlock()
    }
}

