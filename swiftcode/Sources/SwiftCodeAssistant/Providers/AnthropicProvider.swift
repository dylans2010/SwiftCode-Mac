import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Direct Anthropic chat client (Legacy
/// `SwiftCode/Features/AI/LLMService.swift`'s Anthropic path, Dylan's
/// own code, ported under MIT).
///
/// WIRING (wiring-backend): `kind` is now `.anthropic`
/// (`ProviderKind.anthropic`, added in `Core.swift` and wired into the
/// `AssistantBackends.provider(_:)` dispatch). It previously reported
/// `.openRouter`, which misreported the provider in selection, the
/// availability survey and model routing. It is a full
/// `AssistantProvider` so it can be driven by the same `send` /
/// `availability` contract.
/// Why only Anthropic is ported as a direct client: Legacy's Gemini,
/// Mistral and Qwen base URLs are OpenAI-compatible endpoints
/// (`generativelanguage.googleapis.com/v1beta/openai`,
/// `api.mistral.ai/v1`, `dashscope.aliyuncs.com/compatible-mode/v1`)
/// with Bearer auth, so their chat already goes through the
/// destination's `OpenAIProvider` (configurable `baseURL`) and the
/// custom-endpoints path. Anthropic's Messages API is the one wire
/// format that is not OpenAI-compatible (`x-api-key` +
/// `anthropic-version` headers, a top-level `system` field,
/// `max_tokens`, content blocks), so it gets its own provider.
///
/// API key: read from the secret store (`SecretAccount.anthropicKey`)
/// when no key is passed in; never stored by this client.
public struct AnthropicProvider: AssistantProvider {
    public let kind = ProviderKind.anthropic
    public static let defaultBaseURL = "https://api.anthropic.com/v1"
    public static let anthropicVersion = "2023-06-01"

    public var baseURL: String
    public var apiKey: String?

    public init(baseURL: String = Self.defaultBaseURL, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    private func resolvedKey() -> String? {
        if let apiKey, !apiKey.isEmpty { return apiKey }
        return defaultSecretStore().readString(SecretAccount.anthropicKey)
    }

    public func availability() async -> ProviderAvailability {
        guard let key = resolvedKey(), !key.isEmpty else {
            return .signedOut(hint: "No Anthropic API key is stored. Add one in Settings ▸ Coding Assistant.")
        }
        guard let url = HTTP.url(baseURL, "models") else {
            return .failed("The Anthropic address “\(baseURL)” is not a valid URL.")
        }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        do {
            let response = try await HTTP.send(request, timeout: 10)
            if response.status == 401 { return .signedOut(hint: "The Anthropic API key was rejected (401).") }
            guard response.status == 200 else {
                return .failed("Anthropic answered HTTP \(response.status): \(HTTP.errorMessage(response.body).message)")
            }
            let models = Self.parseModels(response.body)
            return models.isEmpty ? .noModels(hint: "Anthropic listed no models.") : .ready(models)
        } catch {
            return HTTP.isUnreachable(error)
                ? .failed("Anthropic is unreachable: \(error.localizedDescription)")
                : .failed(error.localizedDescription)
        }
    }

    static func parseModels(_ body: Data) -> [ModelInfo] {
        guard let object = JSON.object(body), let list = object["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            return ModelInfo(id: id, displayName: id)
        }
    }

    /// The Messages API request body (Legacy `buildRequestBody` for
    /// `.anthropic`): `model`, `max_tokens`, a top-level `system`
    /// field, and `messages` with text content blocks.
    static func requestBody(model: String, instructions: String, messages: [ChatMessage], stream: Bool) -> [String: Any] {
        var body: [String: Any] = ["model": model, "max_tokens": 4096, "stream": stream]
        if !instructions.isEmpty { body["system"] = instructions }
        body["messages"] = messages.map { message in
            ["role": message.role.rawValue, "content": [["type": "text", "text": message.content]]]
        }
        return body
    }

    public func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let provider = self
        return eventStream { out in
            guard let key = provider.resolvedKey(), !key.isEmpty else {
                throw AssistantError.notSignedIn(hint: "No Anthropic API key is stored.")
            }
            guard let url = HTTP.url(provider.baseURL, "messages") else {
                throw AssistantError.failed("The Anthropic address is not a valid URL.")
            }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
            let model = request.model ?? "claude-sonnet-4-5"
            urlRequest.httpBody = try JSONSerialization.data(
                withJSONObject: Self.requestBody(model: model, instructions: request.instructions, messages: request.messages, stream: true),
                options: [.sortedKeys])
            var decoder = SSEDecoder()
            var finished = false
            var usage: TokenUsage?
            func handle(_ event: SSEDecoder.Event) throws -> Bool {
                for chunk in try Self.parseEvent(event.data) {
                    switch chunk {
                    case .text(let text): out.yield(.text(text))
                    case .usage(let tokens): usage = tokens
                    case .done: finished = true; return true
                    case .none: break
                    }
                }
                return false
            }
            do {
                try await HTTP.streamLines(urlRequest, error: { status, body in
                    AssistantError.http(status: status, message: HTTP.errorMessage(body).message)
                }) { line in
                    guard let event = decoder.push(line: line) else { return false }
                    return try handle(event)
                }
                if !finished, let event = decoder.finish() { _ = try handle(event) }
            } catch where HTTP.isUnreachable(error) {
                throw AssistantError.unreachable(service: "Anthropic", url: provider.baseURL, hint: "Check the network connection.")
            }
            if !finished { throw AssistantError.incomplete("Anthropic closed the stream") }
            out.yield(.finished(usage))
        }
    }

    enum AnthropicChunk: Equatable {
        case text(String)
        case usage(TokenUsage)
        case done
        case none
    }

    /// One `data:` payload of the Anthropic Messages stream:
    /// `content_block_delta` carries text, `message_delta` carries
    /// the usage block, `message_stop` ends the message.
    static func parseEvent(_ data: String) throws -> [AnthropicChunk] {
        let trimmed = data.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return [.none] }
        guard let object = JSON.object(trimmed) else {
            throw AssistantError.malformed("Anthropic sent an event that is not JSON.")
        }
        if object["error"] != nil {
            throw AssistantError.failed(HTTP.errorMessage(Data(trimmed.utf8)).message)
        }
        guard let type = object["type"] as? String else { return [.none] }
        switch type {
        case "content_block_delta":
            if let delta = object["delta"] as? [String: Any],
               let text = delta["text"] as? String, !text.isEmpty {
                return [.text(text)]
            }
            return [.none]
        case "message_delta":
            if let usage = object["usage"] as? [String: Any] {
                return [.usage(TokenUsage(inputTokens: JSON.int(usage["input_tokens"]),
                                         outputTokens: JSON.int(usage["output_tokens"])))]
            }
            return [.none]
        case "message_stop":
            return [.done]
        default:
            return [.none]
        }
    }
}
