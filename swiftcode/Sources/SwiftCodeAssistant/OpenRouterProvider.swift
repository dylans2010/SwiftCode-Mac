import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenRouter models through its OpenAI-compatible endpoints
/// (`GET /models`, `POST /chat/completions` streamed as server-sent
/// events), authorized by an API key the user enters. Models come from
/// `GET /models` at run time; SwiftCode names none itself.
///
/// The key arrives through the initializer (the coordinator wires it
/// from the SecretStore account `openrouter.api-key`); it is never
/// hardcoded, never logged, and never written anywhere by this type.
///
/// Ported from Legacy's OpenRouter Assist path
/// (`OpenRouterAssistProvider`, `OpenRouterClient`,
/// `OpenRouterRequestBuilder`, and the OpenRouter part of
/// `AssistModelDiscoveryService`); see
/// `specs/ide/assist-providers-openrouter.md`.
public struct OpenRouterProvider: AssistantProvider {
    public let kind = ProviderKind.openRouter
    /// The API root, without a trailing path (`/models` and
    /// `/chat/completions` are appended).
    public var baseURL: String
    /// Sent as `Authorization: Bearer`; nil or empty means signed out.
    public var apiKey: String?
    public static let defaultBaseURL = "https://openrouter.ai/api/v1"

    static let signedOutHint = "Enter an OpenRouter API key in Settings ▸ Coding Assistant."

    /// How long a discovered model list is reused before `GET /models`
    /// runs again (1 hour). `refreshModels()` bypasses it on demand.
    public static let modelCacheTTL: TimeInterval = 3600

    private let cache = OpenRouterModelCache()

    public init(baseURL: String = Self.defaultBaseURL, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    public func availability() async -> ProviderAvailability {
        do {
            let models = try await listModels()
            return models.isEmpty ? .noModels(hint: "OpenRouter lists no models.") : .ready(models)
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

    /// The discovered models, from the cache when it is fresh, otherwise
    /// from a live `GET /models`. Throws `.notSignedIn` with no key;
    /// throws on discovery failure — there is no bundled or seed
    /// catalog to fall back to, so a failed discovery is reported
    /// honestly instead of showing models that were never listed.
    public func listModels(forceRefresh: Bool = false) async throws -> [ModelInfo] {
        if !forceRefresh, let cached = cache.cached() { return cached }
        let models = Self.parseModels(try await fetchModelsData())
        cache.store(models)
        return models
    }

    /// Re-fetches the model list now, ignoring the cache (the manual
    /// refresh path for Settings).
    public func refreshModels() async throws -> [ModelInfo] {
        try await listModels(forceRefresh: true)
    }

    /// Tests the saved credential against the live `/models` endpoint.
    /// Returns a human-readable success summary; throws a specific
    /// `AssistantError` otherwise. Never logs or returns the key.
    public func testConnection() async throws -> String {
        let models = try await listModels(forceRefresh: true)
        return "Connected to OpenRouter (\(models.count) models available)."
    }

    /// Validates that a model identifier actually exists on OpenRouter
    /// and reports its native tool-calling support. Throws
    /// `.modelNotFound` instead of falling back to another model, and
    /// `.failed` for an identifier that is not in provider/model form.
    public func validateModel(_ modelID: String) async throws -> OpenRouterToolCallingSupport {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("/") else {
            throw AssistantError.failed("“\(trimmed)” is not an OpenRouter model identifier (expected provider/model form).")
        }
        let data = try await fetchModelsData()
        guard let support = Self.toolCallingSupport(for: trimmed, in: data) else {
            throw AssistantError.modelNotFound(model: trimmed, hint: "Choose another model from the discovered list in Settings ▸ Coding Assistant.")
        }
        return support
    }

    public func contextWindow(model: String) async -> Int? {
        (try? await listModels())?.first { $0.id == model }?.contextWindow
    }

    /// The raw `/models` body (HTTP 200). Maps transport and status
    /// failures to `AssistantError` first, so callers never parse an
    /// error body as a model list.
    private func fetchModelsData() async throws -> Data {
        guard let key = apiKey, !key.isEmpty else { throw AssistantError.notSignedIn(hint: Self.signedOutHint) }
        guard let url = HTTP.url(baseURL, "models") else { throw AssistantError.failed("The OpenRouter address is not valid.") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let response: HTTP.Response
        do {
            response = try await HTTP.send(request, timeout: 15)
        } catch where HTTP.isUnreachable(error) {
            throw AssistantError.unreachable(service: "OpenRouter", url: baseURL, hint: "Check the network connection.")
        }
        guard response.status == 200 else { throw Self.mapError(status: response.status, body: response.body, model: "") }
        return response.body
    }

    /// `data[].id` of a `/models` body, with `name` as the display name
    /// (falling back to the id when it is absent or empty) and
    /// `context_length` as the context window when reported. Entries
    /// without an `id` are skipped. Server order is preserved.
    static func parseModels(_ body: Data) -> [ModelInfo] {
        guard let o = JSON.object(body), let list = o["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            let name = m["name"] as? String
            return ModelInfo(id: id, displayName: (name?.isEmpty == false) ? name : id,
                             contextWindow: JSON.int(m["context_length"]))
        }
    }

    /// The native tool-calling support of `modelID` in a `/models`
    /// body, or nil when the model is not listed at all. Legacy's rule,
    /// kept exactly: `supported_parameters` containing `tools` means
    /// native function calling; the field present without `tools` means
    /// it does not support it; the field absent means unknown (the
    /// assistant's JSON tool protocol does not depend on it, so unknown
    /// is not a failure).
    static func toolCallingSupport(for modelID: String, in body: Data) -> OpenRouterToolCallingSupport? {
        guard let o = JSON.object(body), let list = o["data"] as? [[String: Any]],
              let entry = list.first(where: { ($0["id"] as? String) == modelID }) else { return nil }
        guard let supported = entry["supported_parameters"] as? [String] else { return .unknown }
        return supported.contains("tools") ? .supports : .doesNotSupport
    }

    /// The chat-completions request body: instructions as the system
    /// message, then the history, streamed, with
    /// `stream_options.include_usage` asking for the token counts in a
    /// last chunk.
    static func chatBody(_ request: ChatRequest) -> [String: Any] {
        var messages: [[String: Any]] = [["role": "system", "content": request.instructions]]
        messages += request.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        var body: [String: Any] = ["messages": messages, "stream": true, "stream_options": ["include_usage": true]]
        if let m = request.model, !m.isEmpty { body["model"] = m }
        let g = request.generation
        if let n = g.maxOutputTokens { body["max_tokens"] = n }
        if let t = g.temperature { body["temperature"] = t }
        if let p = g.topP { body["top_p"] = p }
        return body
    }

    public func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let provider = self
        return eventStream { out in
            guard let key = provider.apiKey, !key.isEmpty else { throw AssistantError.notSignedIn(hint: Self.signedOutHint) }
            guard let url = HTTP.url(provider.baseURL, "chat/completions") else { throw AssistantError.failed("The OpenRouter address is not valid.") }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: Self.chatBody(request), options: [.sortedKeys])
            var sse = SSEDecoder()
            var finished = false
            var usage: TokenUsage?
            var truncated = false
            func handle(_ e: SSEDecoder.Event) throws -> Bool {
                // The OpenAI chat-completions streaming format, shared
                // with the llama.cpp provider.
                for c in try ChatCompletionsProvider.parseChunk(e.data) {
                    switch c {
                    case .text(let t): out.yield(.text(t))
                    case .usage(let u): usage = u
                    case .length: truncated = true
                    case .done: finished = true; return true
                    case .none: break
                    }
                }
                return false
            }
            do {
                try await HTTP.streamLines(req, error: { status, body in
                    Self.mapError(status: status, body: body, model: request.model ?? "")
                }) { line in
                    guard let e = sse.push(line: line) else { return false }
                    return try handle(e)
                }
                if !finished, let e = sse.finish() { _ = try handle(e) }
            } catch where HTTP.isUnreachable(error) {
                throw AssistantError.unreachable(service: "OpenRouter", url: provider.baseURL, hint: "Check the network connection.")
            }
            if !finished { throw AssistantError.incomplete("the server closed the stream") }
            if truncated { out.yield(.truncated) }
            out.yield(.finished(usage))
        }
    }

    /// Maps an HTTP error to the `AssistantError` with the recovery the
    /// status calls for. A 404 names the model only when the error
    /// message itself names it — a 404 from a wrong base URL must not
    /// be misreported as an unknown model.
    static func mapError(status: Int, body: Data, model: String) -> AssistantError {
        let (message, _) = HTTP.errorMessage(body)
        switch status {
        case 401:
            return .notSignedIn(hint: "The OpenRouter API key was not accepted. Check it in Settings ▸ Coding Assistant.")
        case 402:
            return .failed(message.isEmpty
                ? "OpenRouter reports insufficient credits (402) for this account. Add credits on openrouter.ai; the selected model was not changed."
                : message)
        case 404 where !model.isEmpty && message.contains(model):
            return .modelNotFound(model: model, hint: "Choose another model from the discovered list in Settings ▸ Coding Assistant.")
        case 429:
            return .usageLimit(message.isEmpty ? "OpenRouter rate-limited this request (429). Wait briefly and try again." : message)
        default:
            return .http(status: status, message: message)
        }
    }
}

/// Whether a discovered OpenRouter model advertises native function
/// calling (`supported_parameters` containing `tools`). `.unknown`
/// means the catalog entry carried no such field — the assistant's
/// JSON tool protocol does not depend on it, so unknown is not a
/// failure. Ported from Legacy's `OpenRouterToolCallingSupport`.
public enum OpenRouterToolCallingSupport: Sendable, Equatable {
    case supports
    case doesNotSupport
    case unknown
}

/// The discovered model list, cached for `OpenRouterProvider.modelCacheTTL`.
private final class OpenRouterModelCache: @unchecked Sendable {
    private let lock = NSLock()
    private var models: [ModelInfo]?
    private var fetchedAt: Date?

    func cached() -> [ModelInfo]? {
        lock.lock(); defer { lock.unlock() }
        guard let models, let fetchedAt, Date().timeIntervalSince(fetchedAt) < OpenRouterProvider.modelCacheTTL else { return nil }
        return models
    }

    func store(_ models: [ModelInfo]) {
        lock.lock(); fetchedAt = Date(); self.models = models; lock.unlock()
    }
}
