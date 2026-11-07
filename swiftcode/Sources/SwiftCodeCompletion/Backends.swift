import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeAssistant

public struct PredictionRequest: Sendable, Equatable {
    public var context: CompletionContext
    public var model: String
    public var maxTokens: Int
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var repeatPenalty: Double?
    public var fimFormat: FIMFormat

    public init(context: CompletionContext, model: String = "", maxTokens: Int = 128, temperature: Double? = 0.2,
                topP: Double? = nil, topK: Int? = nil, repeatPenalty: Double? = nil, fimFormat: FIMFormat = .auto) {
        self.repeatPenalty = repeatPenalty
        self.context = context
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.fimFormat = fimFormat
    }

    public init(context: CompletionContext, settings s: PredictiveCompletionSettings) {
        self.init(context: context, model: s.model, maxTokens: s.maxTokens, temperature: s.temperature, topP: s.topP, topK: s.topK, repeatPenalty: s.repeatPenalty, fimFormat: s.fimFormat)
    }
}

public enum PredictionEvent: Sendable, Equatable {
    case text(String)
    case model(String)
    case chat
}

public enum PredictionError: Error, Sendable, Equatable, LocalizedError {
    case unreachable(backend: PredictiveCompletionSettings.Backend, address: String)
    case noModel(String)
    case modelNotFound(String)
    case http(status: Int, message: String)
    case invalidAddress(String)
    case malformed(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let b, let a): "\(b.displayName) is not running at \(a)."
        case .noModel(let m), .malformed(let m), .failed(let m): m
        case .modelNotFound(let m): "The model “\(m)” is not installed."
        case .http(let s, let m): m.isEmpty ? "The server answered HTTP \(s)." : "HTTP \(s): \(m)"
        case .invalidAddress(let a): "“\(a)” is not a valid address."
        }
    }

    public var hint: String? {
        switch self {
        case .unreachable(.ollama, _): OllamaProvider.installHint
        case .unreachable(.llamaServer, _): "Start `llama-server -m <model>.gguf --host 127.0.0.1`, or change the address in Settings ▸ Editing ▸ Completion."
        case .unreachable(.openAICompatible, _): "Start your server, or change the address in Settings ▸ Editing ▸ Completion."
        case .noModel: "Install a code model that supports fill-in-the-middle in Ollama (Settings ▸ Editing ▸ Completion ▸ Download)."
        case .modelNotFound: "Choose an installed model in Settings ▸ Editing ▸ Completion."
        default: nil
        }
    }

    public var isUnreachable: Bool { if case .unreachable = self { true } else { false } }
}

public struct BackendProbe: Sendable, Equatable {
    public var reachable: Bool
    public var models: [String]
    public var fimModels: [String]
    public var message: String
    public init(reachable: Bool, models: [String] = [], fimModels: [String] = [], message: String) {
        self.reachable = reachable
        self.models = models
        self.fimModels = fimModels
        self.message = message
    }
}

public protocol PredictionBackend: Sendable {
    var kind: PredictiveCompletionSettings.Backend { get }
    var address: String { get }
    func stream(_ request: PredictionRequest) -> AsyncThrowingStream<PredictionEvent, Error>
    func probe() async -> BackendProbe
}

extension PredictiveCompletionSettings {
    public func makeBackend(assistantOllamaURL: String? = nil) -> PredictionBackend {
        let a = effectiveAddress(assistantOllamaURL: assistantOllamaURL)
        switch backend {
        case .ollama: return OllamaFIMBackend(address: a)
        case .llamaServer: return LlamaServerInfillBackend(address: a)
        case .openAICompatible: return OpenAICompatibleBackend(address: a)
        }
    }
}

func predictionStream(_ body: @escaping @Sendable (AsyncThrowingStream<PredictionEvent, Error>.Continuation) async throws -> Void)
    -> AsyncThrowingStream<PredictionEvent, Error> {
    AsyncThrowingStream { out in
        let task = Task {
            do {
                try await body(out)
                out.finish()
            } catch {
                out.finish(throwing: HTTP.isCancellation(error) ? CancellationError() : error)
            }
        }
        out.onTermination = { _ in task.cancel() }
    }
}

func jsonObject(_ d: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }
func jsonObject(_ s: String) -> [String: Any]? { jsonObject(Data(s.utf8)) }

public struct OllamaFIMBackend: PredictionBackend {
    public let kind = PredictiveCompletionSettings.Backend.ollama
    public var address: String
    public var keepAlive: String?
    public init(address: String = OllamaProvider.defaultBaseURL) { self.address = address }

    var provider: OllamaProvider { OllamaProvider(baseURL: address) }

    public static func prompt(_ c: CompletionContext) -> String {
        guard !c.related.isEmpty, let mark = CompletionContext.lineComment(for: c.language) else { return c.prefix }
        var s = ""
        for r in c.related {
            s += "\(mark) From \(r.path):\n"
            for l in r.text.split(separator: "\n", omittingEmptySubsequences: false) { s += "\(mark) \(l)\n" }
            s += "\n"
        }
        return s + c.prefix
    }

    func pickModel() async throws -> String {
        let models = try await provider.installedModels()
        let names = models.map(\.id)
        if let m = PickedModels.shared.get(address, names) { return m }
        for m in models where await provider.capabilities(model: m.id)?.contains("insert") == true {
            PickedModels.shared.set(address, names, m.id)
            return m.id
        }
        throw PredictionError.noModel(models.isEmpty ? "Ollama has no models." : "None of Ollama's models can fill in the middle.")
    }

    public func stream(_ request: PredictionRequest) -> AsyncThrowingStream<PredictionEvent, Error> {
        let backend = self
        return predictionStream { out in
            do {
                let model = request.model.isEmpty ? try await backend.pickModel() : request.model
                out.yield(.model(model))
                let c = request.context
                let g = OllamaProvider.GenerateRequest(model: model, prompt: Self.prompt(c), suffix: c.suffix, maxTokens: request.maxTokens,
                                                       temperature: request.temperature, topP: request.topP, topK: request.topK, repeatPenalty: request.repeatPenalty,
                                                       keepAlive: backend.keepAlive)
                for try await e in backend.provider.generate(g) {
                    if case .text(let t) = e { out.yield(.text(t)) }
                }
            } catch let e as AssistantError {
                throw Self.map(e, backend: backend)
            }
        }
    }

    static func map(_ e: AssistantError, backend: OllamaFIMBackend) -> PredictionError {
        switch e {
        case .unreachable: .unreachable(backend: .ollama, address: backend.address)
        case .modelNotFound(let m, _): .modelNotFound(m)
        case .http(let s, let m): .http(status: s, message: m)
        case .malformed(let m): .malformed(m)
        default: .failed(e.localizedDescription)
        }
    }

    public func probe() async -> BackendProbe {
        do {
            let models = try await provider.installedModels().map(\.id)
            var fim: [String] = []
            for m in models where await provider.capabilities(model: m)?.contains("insert") == true { fim.append(m) }
            let msg = models.isEmpty ? "Ollama is running and has no models."
                : (fim.isEmpty ? "Ollama is running; none of its \(models.count) models can fill in the middle."
                               : "Ollama is running: \(fim.count) of \(models.count) models can fill in the middle.")
            return BackendProbe(reachable: true, models: models, fimModels: fim, message: msg)
        } catch {
            return BackendProbe(reachable: false, message: "Ollama is not running at \(address). " + OllamaProvider.installHint)
        }
    }
}

final class PickedModels: @unchecked Sendable {
    static let shared = PickedModels()
    private let lock = NSLock()
    private var picks: [String: ([String], String)] = [:]
    func get(_ address: String, _ models: [String]) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let p = picks[address], p.0 == models else { return nil }
        return p.1
    }
    func set(_ address: String, _ models: [String], _ pick: String) {
        lock.lock(); picks[address] = (models, pick); lock.unlock()
    }
}

public struct LlamaServerInfillBackend: PredictionBackend {
    public let kind = PredictiveCompletionSettings.Backend.llamaServer
    public var address: String
    public init(address: String = ChatCompletionsProvider.defaultBaseURL) { self.address = address }

    public static func body(_ r: PredictionRequest) -> [String: Any] {
        let c = r.context
        var b: [String: Any] = ["input_prefix": c.prefix, "input_suffix": c.suffix, "prompt": "", "n_predict": r.maxTokens,
                                "stream": true, "cache_prompt": true]
        if !c.related.isEmpty { b["input_extra"] = c.related.map { ["filename": $0.path, "text": $0.text] } }
        if let t = r.temperature { b["temperature"] = t }
        if let p = r.topP { b["top_p"] = p }
        if let k = r.topK { b["top_k"] = k }
        if let rp = r.repeatPenalty { b["repeat_penalty"] = rp }
        if !r.model.isEmpty { b["model"] = r.model }
        return b
    }

    public func stream(_ request: PredictionRequest) -> AsyncThrowingStream<PredictionEvent, Error> {
        let a = address
        return predictionStream { out in
            guard let url = HTTP.url(a, "infill") else { throw PredictionError.invalidAddress(a) }
            var req = try HTTP.jsonRequest(url, body: Self.body(request))
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            var sse = SSEDecoder()
            var done = false
            func handle(_ data: String) throws {
                guard let o = jsonObject(data) else { throw PredictionError.malformed("llama-server sent an event that is not JSON.") }
                if let e = o["error"] { throw PredictionError.failed("llama-server: \((e as? [String: Any])?["message"] as? String ?? "\(e)")") }
                if let t = o["content"] as? String, !t.isEmpty { out.yield(.text(t)) }
                if o["stop"] as? Bool == true { done = true }
            }
            do {
                try await HTTP.streamLines(req, error: { s, body in PredictionError.http(status: s, message: HTTP.errorMessage(body).message) }) { line in
                    if let e = sse.push(line: line) { try handle(e.data) }
                    return done
                }
                if !done, let e = sse.finish() { try handle(e.data) }
            } catch where HTTP.isUnreachable(error) {
                throw PredictionError.unreachable(backend: .llamaServer, address: a)
            }
        }
    }

    public func probe() async -> BackendProbe {
        await probeOpenAIModels(address: address, kind: kind, name: "llama-server")
    }
}

public struct OpenAICompatibleBackend: PredictionBackend {
    public let kind = PredictiveCompletionSettings.Backend.openAICompatible
    public var address: String
    public init(address: String = ChatCompletionsProvider.defaultBaseURL) { self.address = address }

    func endpoint(_ path: String) -> URL? {
        let a = address.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return HTTP.url(a.hasSuffix("/v1") ? a : a + "/v1", path)
    }

    public static func completionsBody(_ r: PredictionRequest, prompt: String, stop: [String]) -> [String: Any] {
        var b: [String: Any] = ["prompt": prompt, "max_tokens": r.maxTokens, "stream": true, "stream_options": ["include_usage": true]]
        if !r.model.isEmpty { b["model"] = r.model }
        if !stop.isEmpty { b["stop"] = Array(stop.prefix(4)) }
        if let t = r.temperature { b["temperature"] = t }
        if let p = r.topP { b["top_p"] = p }
        if let k = r.topK { b["top_k"] = k }
        if let rp = r.repeatPenalty { b["repeat_penalty"] = rp }
        return b
    }

    public static func chatBody(_ r: PredictionRequest) -> [String: Any] {
        var b: [String: Any] = ["messages": FIMFormat.chatMessages(r.context), "max_tokens": r.maxTokens, "stream": true,
                                "stream_options": ["include_usage": true]]
        if !r.model.isEmpty { b["model"] = r.model }
        if let t = r.temperature { b["temperature"] = t }
        if let p = r.topP { b["top_p"] = p }
        if let k = r.topK { b["top_k"] = k }
        if let rp = r.repeatPenalty { b["repeat_penalty"] = rp }
        return b
    }

    public func stream(_ request: PredictionRequest) -> AsyncThrowingStream<PredictionEvent, Error> {
        let backend = self
        return predictionStream { out in
            let format = request.fimFormat.resolved(model: request.model)
            let isChat = format == .chat
            guard let url = backend.endpoint(isChat ? "chat/completions" : "completions") else { throw PredictionError.invalidAddress(backend.address) }
            let body = isChat ? Self.chatBody(request)
                : Self.completionsBody(request, prompt: format.prompt(request.context) ?? request.context.prefix, stop: format.stop)
            var req = try HTTP.jsonRequest(url, body: body)
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            if isChat { out.yield(.chat) }
            var sse = SSEDecoder()
            var done = false
            func handle(_ data: String) throws {
                let d = data.trimmingCharacters(in: .whitespaces)
                if d == "[DONE]" { done = true; return }
                guard let o = jsonObject(d) else { throw PredictionError.malformed("The server sent an event that is not JSON.") }
                if o["error"] != nil { throw PredictionError.failed(HTTP.errorMessage(Data(d.utf8)).message) }
                guard let first = (o["choices"] as? [[String: Any]])?.first else { return }
                let t = (first["text"] as? String) ?? ((first["delta"] as? [String: Any])?["content"] as? String)
                if let t, !t.isEmpty { out.yield(.text(t)) }
            }
            do {
                try await HTTP.streamLines(req, error: { s, b in PredictionError.http(status: s, message: HTTP.errorMessage(b).message) }) { line in
                    if let e = sse.push(line: line) { try handle(e.data) }
                    return done
                }
                if !done, let e = sse.finish() { try handle(e.data) }
            } catch where HTTP.isUnreachable(error) {
                throw PredictionError.unreachable(backend: .openAICompatible, address: backend.address)
            }
        }
    }

    public func probe() async -> BackendProbe {
        let a = address.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return await probeOpenAIModels(address: a.hasSuffix("/v1") ? String(a.dropLast(3)) : a, kind: kind, name: "The server")
    }
}

func probeOpenAIModels(address: String, kind: PredictiveCompletionSettings.Backend, name: String) async -> BackendProbe {
    guard let url = HTTP.url(address, "v1/models") else { return BackendProbe(reachable: false, message: "“\(address)” is not a valid address.") }
    do {
        let r = try await HTTP.send(URLRequest(url: url), timeout: 3)
        if r.status == 503 { return BackendProbe(reachable: true, message: "\(name) is still loading its model.") }
        guard r.status == 200 else { return BackendProbe(reachable: true, message: "\(name) answered HTTP \(r.status).") }
        let ids = ((jsonObject(r.body)?["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        return BackendProbe(reachable: true, models: ids, fimModels: ids,
                            message: ids.isEmpty ? "\(name) is running and lists no model." : "\(name) is running: \(ids.joined(separator: ", ")).")
    } catch {
        return BackendProbe(reachable: false, message: "Nothing answers at \(address). " + (PredictionError.unreachable(backend: kind, address: address).hint ?? ""))
    }
}
