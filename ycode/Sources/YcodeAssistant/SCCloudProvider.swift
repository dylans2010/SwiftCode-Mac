import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// SwiftCode's own hosted models ("SwiftCode Cloud") through an
/// OpenAI-compatible HTTP API: `GET /v1/models` lists the models the
/// server actually serves and `POST /v1/chat/completions` answers one
/// prompt. See `specs/ide/assist-providers-sccloud.md`.
///
/// Legacy behaviour ported from `SCCloudModel.swift`:
///   * the wire format is OpenAI-compatible (Legacy's configured format;
///     its Ollama-native alternative is not used here);
///   * authentication is a per-device fingerprint, not an API key: every
///     request carries `X-SwiftCode-Device-Fingerprint: ssc_<sha256 hex>`,
///     generated once when the cloud model is enabled and stored by the
///     host (Legacy keeps it in the Keychain; see
///     `provisionFingerprint()`). No `Authorization` header is ever sent.
///   * fair use is 10 requests per rolling 24-hour window, enforced
///     locally and (by the header) server-side; any completed HTTP
///     round-trip counts, success or failure;
///   * model names are canonicalized by stripping a trailing `:latest`
///     tag, and discovery results are cached with a 1-hour TTL.
///
/// The endpoint is CONFIGURABLE and has NO default in this source: the
/// Legacy default was an ephemeral tunnel that is dead, so an
/// unconfigured provider reports itself honestly unavailable instead of
/// pointing anywhere. The coordinator wires `settings.scCloudURL` (empty
/// by default) and the provisioned fingerprint into this provider.
public struct SCCloudProvider: AssistantProvider {
    public let kind = ProviderKind.scCloud

    /// The server's base URL, without a trailing `/v1` (the provider
    /// appends the paths itself). Empty means "not configured".
    public var baseURL: String
    /// The device fingerprint (`ssc_…`), provisioned by the host and
    /// stored in its secret store. Nil until the host provisions one.
    public var fingerprint: String?

    /// Header carrying the device fingerprint on every cloud request.
    public static let fingerprintHeaderName = "X-SwiftCode-Device-Fingerprint"
    /// Fair-use policy, as in Legacy: at most this many requests per
    /// rolling 24-hour window.
    public static let dailyRequestLimit = 10
    public static let rateLimitWindow: TimeInterval = 24 * 60 * 60
    /// How long a chat request may take. Generous on purpose: on a small
    /// server a cold model load plus slow generation can take minutes.
    public static let requestTimeout: TimeInterval = 180

    /// What `availability()` reports while no endpoint is configured.
    /// It names exactly what Dylan must supply: a real SCCloud endpoint
    /// URL. The device fingerprint is generated automatically, so no
    /// credential has to be supplied by hand.
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

    /// True once the base URL is a real URL with a host. HTTPS is
    /// required, except for loopback hosts (`127.0.0.1` / `localhost`),
    /// which exist only so tests and local development servers can use
    /// plain HTTP.
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

    /// The models the endpoint serves, from the cache when fresh (TTL:
    /// 1 hour, see `SCCloudModelCache`), otherwise fetched live. A failed
    /// fetch keeps the previous list when one exists.
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
            // A failed refresh never wipes the previous list: serve the
            // last known models when there are any.
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
            // Any completed HTTP round-trip counts against the daily quota,
            // success or failure — the request reached the backend.
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

    /// Resolves the exact server-side model name for a chat request:
    /// an explicit model first (a Legacy-style `swiftcode-cloud:<name>`
    /// internal ID is unwrapped to `<name>`), otherwise the first
    /// discovered model. Never a hardcoded model name.
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

    // MARK: - Wire shapes

    /// OpenAI-style model list: `{ "data": [ { "id": "…", "owned_by": "…" } ] }`.
    /// IDs are canonicalized (`name:latest` → `name`), deduplicated, and
    /// sorted by name. No model is ever named here.
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

    /// A discovered model ID with a trailing `:latest` tag stripped, so
    /// the name matches the server's documented call convention (bare
    /// aliases); every other tag is kept verbatim.
    static func canonicalModelName(_ discoveredID: String) -> String {
        let trimmed = discoveredID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(":latest") { return String(trimmed.dropLast(":latest".count)) }
        return trimmed
    }

    /// Legacy internal-ID scheme: `swiftcode-cloud:<name>` (and the bare
    /// `swiftcode-cloud` legacy single-model ID, which resolves to nil —
    /// it names no server-side model). Returns the endpoint name, or nil
    /// when `id` is not a cloud internal ID.
    static func endpointName(forInternalID id: String) -> String? {
        guard id == internalIDPrefix || id.hasPrefix(internalIDPrefix + ":") else { return nil }
        guard id != internalIDPrefix else { return nil }
        return canonicalModelName(String(id.dropFirst(internalIDPrefix.count + 1)))
    }

    /// Whether `id` is a SwiftCode Cloud internal ID: the bare legacy
    /// `swiftcode-cloud` or a per-model `swiftcode-cloud:<name>`.
    /// Legacy `SCCloudConfiguration.isCloudModelID` (Wave 15 router).
    static func isCloudModelID(_ id: String) -> Bool {
        id == internalIDPrefix || id.hasPrefix(internalIDPrefix + ":")
    }

    /// The prefix of Legacy's internal cloud-model IDs.
    static let internalIDPrefix = "swiftcode-cloud"

    /// Display name for a cloud model with no endpoint name
    /// (Legacy `SCCloudConfiguration.displayName`).
    static let displayNameFallback = "SwiftCode Cloud Model"

    /// The chat-completion reply text. Accepts, in order:
    ///   1. OpenAI-style `choices[0].message.content`
    ///   2. Ollama-style `message.content` (native `/api/chat`, non-streaming)
    ///   3. Common single-string shapes (`response`, `output`, `text`,
    ///      `content`, `result`, `answer`)
    ///   4. A bare non-empty string body.
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

    /// Maps a non-2xx HTTP response. A tunnel-error signature (HTTP 530,
    /// or an HTML error body) is reported as temporarily unavailable
    /// rather than as a generic HTTP error, as in Legacy.
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

    /// Generates a device fingerprint: `ssc_` + hex(SHA-256(random
    /// 32 bytes)). The host calls this once when the cloud model is
    /// first enabled and stores the result in its secret store; the
    /// value — never the material behind it — is what the backend sees.
    /// (Legacy derived the same `ssc_` shape deterministically from
    /// stable hardware identifiers via CryptoKit; this host has no
    /// hardware-identity API in the portable target, so a stored random
    /// identity is the equivalent that survives app restarts.)
    public static func provisionFingerprint() -> String {
        "ssc_" + SHA256.hash(SecureRandom.bytes(32)).map { String(format: "%02x", $0) }.joined()
    }
}

/// In-memory discovery cache: the last model list, how fresh it is, and
/// which endpoint it came from. A list from another endpoint is evicted
/// immediately, as in Legacy. TTL: 1 hour (`cacheTTL`).
///
/// Deliberate deviation from Legacy: this cache is in-memory only.
/// Legacy also persisted the list to Application Support; a host restart
/// here simply re-discovers (a failed refresh still keeps the previous
/// in-session list).
public final class SCCloudModelCache: @unchecked Sendable {
    /// How long a fetched model list is considered fresh.
    public static let cacheTTL: TimeInterval = 60 * 60

    private let lock = NSLock()
    private var models: [ModelInfo]?
    private var updatedAt: Date?
    private var endpointURL: String?

    public init() {}

    /// The cached list when it is for `endpoint` and younger than the
    /// TTL; nil otherwise (stale, missing, or from another endpoint).
    func modelsIfFresh(for endpoint: String) -> [ModelInfo]? {
        lock.lock()
        defer { lock.unlock() }
        guard endpointURL == endpoint, let models, let updatedAt,
              Date().timeIntervalSince(updatedAt) <= Self.cacheTTL else { return nil }
        return models
    }

    /// The best-known list regardless of age (for a failed refresh to
    /// fall back to), or nil when there is none for this endpoint.
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

/// Fair-use gate: at most `limit` requests per rolling `window`.
/// Timestamps live in memory only (Legacy persisted them to Application
/// Support so the quota survived restarts; this host's quota therefore
/// resets on restart — the backend enforces the same limit
/// independently via the fingerprint header, so the cap itself is not
/// bypassed).
public final class SCCloudRateLimiter: @unchecked Sendable {
    public static let shared = SCCloudRateLimiter()

    public struct Gate: Sendable {
        public let allowed: Bool
        public let remaining: Int
        public let retryAfter: TimeInterval?
    }

    private let lock = NSLock()
    private var timestamps: [Date] = []
    private let limit: Int
    private let window: TimeInterval

    public init(limit: Int = SCCloudProvider.dailyRequestLimit, window: TimeInterval = SCCloudProvider.rateLimitWindow) {
        self.limit = limit
        self.window = window
    }

    /// Evaluates the gate WITHOUT consuming quota.
    public func checkGate() -> Gate {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        timestamps = timestamps.filter { now.timeIntervalSince($0) < window }
        let remaining = max(0, limit - timestamps.count)
        if timestamps.count >= limit, let oldest = timestamps.min() {
            return Gate(allowed: false, remaining: 0, retryAfter: max(0, window - now.timeIntervalSince(oldest)))
        }
        return Gate(allowed: true, remaining: remaining, retryAfter: nil)
    }

    /// Records one completed request against the quota.
    public func recordRequest() {
        lock.lock()
        defer { lock.unlock() }
        timestamps.append(Date())
        let cutoff = Date().addingTimeInterval(-window * 2)
        timestamps = timestamps.filter { $0 > cutoff }
    }

    public var remainingToday: Int { checkGate().remaining }

    public static func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int((interval / 60).rounded(.up)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
