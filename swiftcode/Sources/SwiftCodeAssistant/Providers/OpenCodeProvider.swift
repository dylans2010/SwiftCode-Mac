import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenCodeProvider: AssistantProvider {
    public let kind = ProviderKind.openCode
    public var baseURL: String
    public var agentName: String
    public static let defaultBaseURL = "http://127.0.0.1:4096"
    public static let defaultAgentName = "swiftcode"
    public static let defaultContextWindow = 128_000
    public static let modelCacheTTL: TimeInterval = 3600

    private let modelCache = OpenCodeModelCache()
    private let sessions = OpenCodeSessionStore()

    public init(baseURL: String = Self.defaultBaseURL, agentName: String = Self.defaultAgentName) {
        self.baseURL = baseURL
        self.agentName = agentName
    }

    var notRunningHint: String {
        "Start it with `opencode serve` (install the OpenCode CLI first with `npm install -g opencode-ai` if needed), or change its address in Settings ▸ Coding Assistant."
    }
    static var noModelsHint: String {
        "OpenCode lists no models. Configure a model provider in OpenCode first, then refresh."
    }

    public func refreshModels() { modelCache.clear() }

    public func resetSessions() { sessions.removeAll() }

    public func resetSession(directory: String?) { sessions.remove(key: directory ?? "") }

    public func availability() async -> ProviderAvailability {
        if let cached = modelCache.cached(ttl: Self.modelCacheTTL) { return .ready(cached) }
        guard let url = endpointURL("config/providers", directory: nil) else {
            return .failed("The OpenCode address “\(baseURL)” is not a valid URL.")
        }
        do {
            let r = try await HTTP.send(URLRequest(url: url), timeout: 5)
            if r.status == 401 {
                return .failed("OpenCode requires server authentication, which SwiftCode does not handle. Run it on loopback without server auth.")
            }
            guard r.status == 200 else {
                return .failed("OpenCode answered HTTP \(r.status): \(HTTP.errorMessage(r.body).message)")
            }
            let models = Self.parseModels(r.body)
            guard !models.isEmpty else { return .noModels(hint: Self.noModelsHint) }
            modelCache.store(models)
            return .ready(models)
        } catch {
            return HTTP.isUnreachable(error)
                ? .notRunning(hint: "OpenCode is not running at \(baseURL). " + notRunningHint)
                : .failed(error.localizedDescription)
        }
    }

    public static func parseModels(_ body: Data) -> [ModelInfo] {
        guard let root = try? JSONSerialization.jsonObject(with: body) else { return [] }
        var providerDicts: [[String: Any]] = []

        func collectProviders(from value: Any) {
            if let array = value as? [[String: Any]] {
                providerDicts.append(contentsOf: array)
            } else if let dict = value as? [String: Any] {
                if let providers = dict["providers"] {
                    collectProviders(from: providers)
                } else {
                    for (key, entry) in dict {
                        if var entryDict = entry as? [String: Any] {
                            if entryDict["id"] == nil { entryDict["id"] = key }
                            providerDicts.append(entryDict)
                        } else if let entryArray = entry as? [[String: Any]] {
                            for var modelDict in entryArray {
                                if modelDict["id"] == nil { modelDict["id"] = key }
                                providerDicts.append(["id": key, "models": [modelDict]])
                            }
                        }
                    }
                }
            }
        }
        collectProviders(from: root)

        var models: [ModelInfo] = []
        var seen = Set<String>()
        for provider in providerDicts {
            guard let providerID = (provider["id"] as? String)
                ?? (provider["providerID"] as? String)
                ?? (provider["name"] as? String),
                !providerID.isEmpty else { continue }
            let modelDicts: [[String: Any]]
            if let array = provider["models"] as? [[String: Any]] {
                modelDicts = array
            } else if let dict = provider["models"] as? [String: Any] {
                modelDicts = dict.map { key, value -> [String: Any] in
                    var model = (value as? [String: Any]) ?? [:]
                    if model["id"] == nil { model["id"] = key }
                    return model
                }
            } else {
                continue
            }
            for modelDict in modelDicts {
                guard let modelID = (modelDict["id"] as? String)
                    ?? (modelDict["modelID"] as? String),
                    !modelID.isEmpty else { continue }
                let id = OpenCodeModelID(providerID: providerID, modelID: modelID)
                if seen.insert(id.storedID).inserted {
                    models.append(ModelInfo(id: id.storedID, displayName: id.displayName))
                }
            }
        }
        return models.sorted {
            let a = parseStoredID($0.id), b = parseStoredID($1.id)
            if a?.providerID != b?.providerID { return (a?.providerID ?? "") < (b?.providerID ?? "") }
            return (a?.modelID ?? "") < (b?.modelID ?? "")
        }
    }

    public func contextWindow(model: String) async -> Int? { Self.defaultContextWindow }

    static func promptBody(_ request: ChatRequest, model: OpenCodeModelID, agent: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": ["providerID": model.providerID, "modelID": model.modelID],
            "agent": agent,
            "parts": [["type": "text", "text": promptText(request)]],
        ]
        if !request.messages.isEmpty, !request.instructions.isEmpty {
            body["system"] = request.instructions
        }
        return body
    }

    static func promptText(_ request: ChatRequest) -> String {
        guard !request.messages.isEmpty else { return request.instructions }
        return request.messages.map { "<\($0.role.rawValue)>\n\($0.content)\n</\($0.role.rawValue)>" }.joined(separator: "\n")
    }

    public func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let provider = self
        return eventStream { out in
            guard let model = Self.parseStoredID(request.model) else {
                throw AssistantError.modelNotFound(
                    model: request.model ?? "",
                    hint: "Choose an OpenCode model in Settings ▸ Coding Assistant.")
            }
            let directory = request.workingDirectory?.path
            var sessionID = try await provider.sessionID(directory: directory)
            guard let eventURL = provider.endpointURL("event", directory: directory) else {
                throw AssistantError.failed("The OpenCode address “\(provider.baseURL)” is not a valid URL.")
            }
            var eventRequest = URLRequest(url: eventURL)
            eventRequest.timeoutInterval = 3600
            eventRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            let stream = HTTP.stream(eventRequest, timeout: 3600)
            do {
                var prompted = false
                for attempt in 0..<2 where !prompted {
                    do {
                        try await provider.postPrompt(sessionID: sessionID, model: model, request: request, directory: directory)
                        prompted = true
                    } catch let e as AssistantError {
                        if case .failed(let m) = e, m.contains("status 404"), attempt == 0 {
                            provider.sessions.remove(key: directory ?? "")
                            sessionID = try await provider.sessionID(directory: directory)
                        } else {
                            throw e
                        }
                    }
                }
            } catch {
                provider.cancelStream(stream)
                throw error
            }

            var sse = SSEDecoder()
            var splitter = LineSplitter()
            var status = 0
            var errorBody = Data()
            var finished = false
            do {
                for try await chunk in stream {
                    switch chunk {
                    case .head(let s, _):
                        status = s
                    case .body(let d):
                        if !(200..<300).contains(status) { errorBody.append(d); continue }
                        for line in splitter.push(d) {
                            guard let e = sse.push(line: line) else { continue }
                            if try provider.handle(eventData: e.data, sessionID: sessionID, directory: directory, out: out) {
                                finished = true
                            }
                            if finished { break }
                        }
                        if finished { break }
                    }
                }
                if !finished, let last = splitter.finish(), let e = sse.push(line: last) {
                    finished = try provider.handle(eventData: e.data, sessionID: sessionID, directory: directory, out: out)
                }
                if !finished, let e = sse.finish() {
                    finished = try provider.handle(eventData: e.data, sessionID: sessionID, directory: directory, out: out)
                }
            } catch is CancellationError {
                provider.fireAbort(sessionID: sessionID, directory: directory)
                throw CancellationError()
            } catch where HTTP.isUnreachable(error) {
                throw AssistantError.unreachable(service: "OpenCode", url: provider.baseURL, hint: provider.notRunningHint)
            }
            if !(200..<300).contains(status) {
                provider.fireAbort(sessionID: sessionID, directory: directory)
                throw AssistantError.failed("OpenCode event stream returned status \(status). The prompt may still be running on the server; abort it from the OpenCode session if needed.")
            }
            if !finished { throw AssistantError.incomplete("the server closed the stream") }
            out.yield(.finished(nil))
        }
    }

    func handle(eventData data: String, sessionID: String, directory: String?, out: AsyncThrowingStream<ChatEvent, Error>.Continuation) throws -> Bool {
        guard let (eventSessionID, event) = Self.parseEvent(data) else { return false }
        if let eventSessionID, eventSessionID != sessionID { return false }
        switch event {
        case .text(let t):
            out.yield(.text(t))
            return false
        case .tool:
            fireAbort(sessionID: sessionID, directory: directory)
            throw AssistantError.failed(
                "OpenCode attempted to execute a tool on a SwiftCode session. " +
                "Configure the `swiftcode` agent on the server with every permission " +
                "denied (see Settings ▸ Coding Assistant ▸ OpenCode), then retry. The run was aborted.")
        case .idle:
            return true
        case .error(let message):
            throw AssistantError.failed(message)
        case .ignored:
            return false
        }
    }

    enum OpenCodeStreamEvent: Equatable, Sendable {
        case text(String)
        case tool
        case idle
        case error(String)
        case ignored
    }

    static func parseEvent(_ data: String) -> (sessionID: String?, event: OpenCodeStreamEvent)? {
        let payload = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard payload != "[DONE]", !payload.isEmpty,
              let jsonData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        let type = json["type"] as? String ?? ""
        let properties = json["properties"] as? [String: Any] ?? [:]
        let sessionID = (properties["sessionID"] as? String)
            ?? (properties["sessionId"] as? String)
            ?? (properties["session_id"] as? String)

        if type == "session.idle" { return (sessionID, .idle) }
        if type == "session.error" {
            let message: String
            if let error = properties["error"] as? [String: Any], let text = error["message"] as? String {
                message = text
            } else if let text = properties["message"] as? String {
                message = text
            } else {
                message = "OpenCode session reported an error."
            }
            return (sessionID, .error(message))
        }
        if type.contains("part.delta") || type == "message.part.delta" {
            if let part = properties["part"] as? [String: Any] {
                let partType = part["type"] as? String ?? ""
                if partType == "tool" { return (sessionID, .tool) }
                if partType == "text", let text = part["text"] as? String, !text.isEmpty {
                    return (sessionID, .text(text))
                }
            }
            if let delta = properties["delta"] as? String, !delta.isEmpty {
                return (sessionID, .text(delta))
            }
            return (sessionID, .ignored)
        }
        if type.contains("part.updated") || type.contains("part.added") {
            if let part = properties["part"] as? [String: Any], (part["type"] as? String) == "tool" {
                return (sessionID, .tool)
            }
            return (sessionID, .ignored)
        }
        return (sessionID, .ignored)
    }

    func sessionID(directory: String?) async throws -> String {
        let key = directory ?? ""
        if let cached = sessions.id(for: key) { return cached }
        guard let url = endpointURL("session", directory: directory) else {
            throw AssistantError.failed("The OpenCode address “\(baseURL)” is not a valid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": "SwiftCode Assist"])
        let r: HTTP.Response
        do {
            r = try await HTTP.send(request, timeout: 15)
        } catch where HTTP.isUnreachable(error) {
            throw AssistantError.unreachable(service: "OpenCode", url: baseURL, hint: notRunningHint)
        }
        guard (200...299).contains(r.status) else {
            throw AssistantError.failed("Failed to create an OpenCode session (status \(r.status))" +
                (r.text.isEmpty ? "." : ": \(String(r.text.prefix(300)))"))
        }
        guard let json = JSON.object(r.body),
              let id = (json["id"] as? String)
                ?? ((json["data"] as? [String: Any])?["id"] as? String)
                ?? ((json["session"] as? [String: Any])?["id"] as? String),
              !id.isEmpty else {
            throw AssistantError.failed("OpenCode session creation returned no session id.")
        }
        sessions.set(id, for: key)
        return id
    }

    func postPrompt(sessionID: String, model: OpenCodeModelID, request: ChatRequest, directory: String?) async throws {
        guard let url = endpointURL("session/\(sessionID)/prompt_async", directory: directory) else {
            throw AssistantError.failed("The OpenCode address “\(baseURL)” is not a valid URL.")
        }
        var req = try HTTP.jsonRequest(url, body: Self.promptBody(request, model: model, agent: agentName))
        req.timeoutInterval = 30
        let r: HTTP.Response
        do {
            r = try await HTTP.send(req, timeout: 30)
        } catch where HTTP.isUnreachable(error) {
            throw AssistantError.unreachable(service: "OpenCode", url: baseURL, hint: notRunningHint)
        }
        guard (200...299).contains(r.status) else {
            let bodyText = r.text
            if r.status == 404, bodyText.lowercased().contains("agent") {
                throw AssistantError.failed(
                    "OpenCode does not recognise the `\(agentName)` agent. " +
                    "Create it on the server (see Settings ▸ Coding Assistant ▸ OpenCode for the definition) " +
                    "and retry; without it, SwiftCode cannot guarantee its own tool loop.")
            }
            throw AssistantError.failed("OpenCode prompt failed (status \(r.status))" +
                (bodyText.isEmpty ? "." : ": \(String(bodyText.prefix(300)))"))
        }
    }

    func fireAbort(sessionID: String, directory: String?) {
        guard let url = endpointURL("session/\(sessionID)/abort", directory: directory) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        Task { _ = try? await HTTP.send(request, timeout: 5) }
    }

    func cancelStream(_ stream: AsyncThrowingStream<HTTP.Chunk, Error>) {
        let task = Task { for try await _ in stream { } }
        task.cancel()
    }

    func endpointURL(_ path: String, directory: String?) -> URL? {
        guard let base = URL(string: baseURL) else { return nil }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        let basePath = components?.path ?? ""
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        components?.path = trimmedBase + "/" + path
        if let directory, !directory.isEmpty {
            components?.queryItems = [URLQueryItem(name: "directory", value: directory)]
        }
        return components?.url
    }

    static func parseStoredID(_ storedID: String?) -> OpenCodeModelID? {
        guard var remainder = storedID, !remainder.isEmpty else { return nil }
        if remainder.hasPrefix("opencode:") { remainder = String(remainder.dropFirst("opencode:".count)) }
        guard let slash = remainder.firstIndex(of: "/") else { return nil }
        let providerID = String(remainder[..<slash])
        let modelID = String(remainder[remainder.index(after: slash)...])
        guard !providerID.isEmpty, !modelID.isEmpty else { return nil }
        return OpenCodeModelID(providerID: providerID, modelID: modelID)
    }
}

final class OpenCodeModelCache: @unchecked Sendable {
    private let lock = NSLock()
    private var models: [ModelInfo]?
    private var fetchedAt: Date?

    func cached(ttl: TimeInterval) -> [ModelInfo]? {
        lock.lock()
        defer { lock.unlock() }
        guard let models, let fetchedAt, Date().timeIntervalSince(fetchedAt) < ttl else { return nil }
        return models
    }

    func store(_ models: [ModelInfo]) {
        lock.lock()
        defer { lock.unlock() }
        self.models = models
        self.fetchedAt = Date()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        models = nil
        fetchedAt = nil
    }
}

final class OpenCodeSessionStore: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String: String] = [:]

    func id(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return ids[key]
    }

    func set(_ id: String, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        ids[key] = id
    }

    func remove(key: String) {
        lock.lock()
        defer { lock.unlock() }
        ids.removeValue(forKey: key)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        ids.removeAll()
    }
}
