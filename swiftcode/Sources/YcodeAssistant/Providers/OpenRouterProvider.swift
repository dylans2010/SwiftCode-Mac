import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenRouterProvider: AssistantProvider {
    public let kind = ProviderKind.openRouter
    public var baseURL: String
    public var apiKey: String?
    public static let defaultBaseURL = "https://openrouter.ai/api/v1"

    static let signedOutHint = "Enter an OpenRouter API key in Settings ▸ Coding Assistant."

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

    public func listModels(forceRefresh: Bool = false) async throws -> [ModelInfo] {
        if !forceRefresh, let cached = cache.cached() { return cached }
        let models = Self.parseModels(try await fetchModelsData())
        cache.store(models)
        return models
    }

    public func refreshModels() async throws -> [ModelInfo] {
        try await listModels(forceRefresh: true)
    }

    public func testConnection() async throws -> String {
        let models = try await listModels(forceRefresh: true)
        return "Connected to OpenRouter (\(models.count) models available)."
    }

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

    static func parseModels(_ body: Data) -> [ModelInfo] {
        guard let o = JSON.object(body), let list = o["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            let name = m["name"] as? String
            var pricing: ModelInfo.ModelPricing?
            if let rawPricing = m["pricing"] as? [String: Any] {
                let prompt = rawPricing["prompt"] as? String
                let completion = rawPricing["completion"] as? String
                if prompt != nil || completion != nil {
                    pricing = ModelInfo.ModelPricing(prompt: prompt, completion: completion)
                }
            }
            return ModelInfo(id: id, displayName: (name?.isEmpty == false) ? name : id,
                             contextWindow: JSON.int(m["context_length"]),
                             description: m["description"] as? String,
                             pricing: pricing)
        }
    }

    static func toolCallingSupport(for modelID: String, in body: Data) -> OpenRouterToolCallingSupport? {
        guard let o = JSON.object(body), let list = o["data"] as? [[String: Any]],
              let entry = list.first(where: { ($0["id"] as? String) == modelID }) else { return nil }
        guard let supported = entry["supported_parameters"] as? [String] else { return .unknown }
        return supported.contains("tools") ? .supports : .doesNotSupport
    }

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

public enum OpenRouterToolCallingSupport: Sendable, Equatable {
    case supports
    case doesNotSupport
    case unknown
}

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
