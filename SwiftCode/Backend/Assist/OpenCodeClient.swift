import Foundation
import os

private let openCodeLogger = Logger(subsystem: "com.swiftcode.app", category: "OpenCodeClient")

// MARK: - OpenCode errors
//
// Messages are user-facing and never include server URLs with embedded
// credentials, request bodies, or model-provider keys (SwiftCode never
// holds those keys for OpenCode — they live in OpenCode's own config).

public enum OpenCodeError: LocalizedError, Equatable {
    case serverUnavailable(String)
    case invalidConfiguration(String)
    case sessionFailed(String)
    case modelUnavailable(String)
    case streamInterrupted(String)
    case agentNotFound(String)
    /// The server executed (or attempted) a tool on a SwiftCode session.
    /// SwiftCode sessions must be pure-model sessions: the `swiftcode`
    /// agent denies every tool, so any tool part means the server is not
    /// configured that way. Fail closed instead of surfacing a
    /// provider-executed result as a SwiftCode tool result.
    case toolExecutionBlocked(String)

    public var errorDescription: String? {
        switch self {
        case .serverUnavailable(let detail): return detail
        case .invalidConfiguration(let detail): return detail
        case .sessionFailed(let detail): return detail
        case .modelUnavailable(let detail): return detail
        case .streamInterrupted(let detail): return detail
        case .agentNotFound(let detail): return detail
        case .toolExecutionBlocked(let detail): return detail
        }
    }
}

// MARK: - Defensive parsing of `GET /config/providers`

/// Parses the OpenCode provider catalog without assuming one exact shape:
/// the endpoint has returned both a `providers` array and provider-keyed
/// objects across versions, and model entries use `id` or `modelID`.
/// Anything unrecognised is skipped rather than fabricated into a model.
public enum OpenCodeProviderCatalog {
    public static func parseModels(from data: Data) -> [OpenCodeModel] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var providerDicts: [[String: Any]] = []

        func collectProviders(from value: Any) {
            if let array = value as? [[String: Any]] {
                providerDicts.append(contentsOf: array)
            } else if let dict = value as? [String: Any] {
                if let providers = dict["providers"] {
                    collectProviders(from: providers)
                } else {
                    // Provider-keyed object: { "anthropic": { "models": [...] }, … }
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

        var models: [OpenCodeModel] = []
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
                let model = OpenCodeModel(providerID: providerID, modelID: modelID)
                if seen.insert(model.storedID).inserted {
                    models.append(model)
                }
            }
        }
        return models.sorted {
            if $0.providerID != $1.providerID { return $0.providerID < $1.providerID }
            return $0.modelID < $1.modelID
        }
    }
}

// MARK: - Event-stream parsing

/// One parsed OpenCode SSE frame. Only the shapes SwiftCode acts on are
/// distinguished; everything else is `.ignored` so a new event type from
/// a newer server can never be mistaken for model text or a tool result.
enum OpenCodeEvent {
    enum Kind {
        case textDelta(String)
        case tool
        case idle
        case error(String)
        case ignored
    }

    case parsed(sessionID: String?, kind: Kind)

    static func parse(line: String) -> OpenCodeEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let type = json["type"] as? String ?? ""
        let properties = json["properties"] as? [String: Any] ?? [:]
        let sessionID = (properties["sessionID"] as? String)
            ?? (properties["sessionId"] as? String)
            ?? (properties["session_id"] as? String)

        if type == "session.idle" {
            return .parsed(sessionID: sessionID, kind: .idle)
        }
        if type == "session.error" {
            let message: String
            if let error = properties["error"] as? [String: Any],
               let text = error["message"] as? String {
                message = text
            } else if let text = properties["message"] as? String {
                message = text
            } else {
                message = "OpenCode session reported an error."
            }
            return .parsed(sessionID: sessionID, kind: .error(message))
        }
        if type.contains("part.delta") || type == "message.part.delta" {
            if let part = properties["part"] as? [String: Any] {
                let partType = part["type"] as? String ?? ""
                if partType == "tool" {
                    return .parsed(sessionID: sessionID, kind: .tool)
                }
                if partType == "text", let text = part["text"] as? String, !text.isEmpty {
                    return .parsed(sessionID: sessionID, kind: .textDelta(text))
                }
            }
            if let delta = properties["delta"] as? String, !delta.isEmpty {
                return .parsed(sessionID: sessionID, kind: .textDelta(delta))
            }
            return .parsed(sessionID: sessionID, kind: .ignored)
        }
        if type.contains("part.updated") || type.contains("part.added") {
            if let part = properties["part"] as? [String: Any],
               (part["type"] as? String) == "tool" {
                return .parsed(sessionID: sessionID, kind: .tool)
            }
            // Text `updated` frames carry the full accumulated part, not a
            // delta; yielding them would duplicate every delta already
            // streamed, so they are deliberately ignored.
            return .parsed(sessionID: sessionID, kind: .ignored)
        }
        return .parsed(sessionID: sessionID, kind: .ignored)
    }
}

// MARK: - Native OpenCode server client

/// Talks to an OpenCode server over its HTTP + SSE API, with no JS
/// runtime, no bundled server, and no dependency on @opencode-ai/sdk.
/// The server is loopback by default and is never exposed by SwiftCode:
/// SwiftCode only ever connects out to the configured URL.
///
/// Lifecycle: by default SwiftCode connects to a server the user runs
/// (`opencode serve --hostname 127.0.0.1 --port 4096`). With
/// `managedServerEnabled` (opt-in, loopback only) it may start that
/// server from the `opencode` binary on PATH and stops it on request.
public actor OpenCodeClient {
    public static let shared = OpenCodeClient()

    private var sessionsByDirectory: [String: String] = [:]
    private var managedProcess: Process?
    private let urlSession = URLSession(configuration: .default)

    private init() {}

    // MARK: Configuration

    public func configuration() -> OpenCodeConfiguration {
        OpenCodeConfiguration.load()
    }

    public func resetSession(directory: String?) {
        sessionsByDirectory.removeValue(forKey: directory ?? "")
    }

    /// Drops every cached OpenCode session id. Called when the user
    /// switches providers in Settings so a later OpenCode run can never
    /// resume a session from a previous provider selection.
    public func resetAllSessions() {
        sessionsByDirectory.removeAll()
    }

    // MARK: Health

    /// GET /global/health. A 200 is healthy; a 401 means the server
    /// requires authentication SwiftCode deliberately does not handle
    /// (keep the server on loopback without server auth instead).
    public func checkHealth() async -> Bool {
        let config = OpenCodeConfiguration.load()
        guard let url = endpointURL(config: config, path: "global/health", directory: nil) else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                return status.lowercased() == "healthy"
            }
            return true
        } catch {
            return false
        }
    }

    /// Throws a user-actionable error when no server is reachable. Starts
    /// a managed server only when the user opted in.
    public func ensureServer() async throws {
        if await checkHealth() { return }
        let config = OpenCodeConfiguration.load()
        guard config.managedServerEnabled else {
            throw OpenCodeError.serverUnavailable(
                "No OpenCode server is running at \(config.serverURL.absoluteString). " +
                "Start one with `opencode serve --hostname 127.0.0.1 --port \(config.port)` " +
                "and try again, or turn on Managed server in Assist Settings."
            )
        }
        try startManagedServer(config: config)
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { break }
            if await checkHealth() { return }
        }
        throw OpenCodeError.serverUnavailable(
            "Started an OpenCode server, but it did not become healthy at " +
            "\(config.serverURL.absoluteString) within 30 seconds. Check that the " +
            "`opencode` binary works and the port is free."
        )
    }

    // MARK: Managed server (opt-in)

    public func startManagedServer(config: OpenCodeConfiguration? = nil) throws {
        let config = config ?? OpenCodeConfiguration.load()
        guard config.isLoopback else {
            throw OpenCodeError.invalidConfiguration(
                "Managed OpenCode server startup is only supported for loopback URLs."
            )
        }
        if let process = managedProcess, process.isRunning { return }
        guard let binaryPath = findBinary(named: "opencode") else {
            throw OpenCodeError.invalidConfiguration(
                "Managed server is on, but no `opencode` binary was found on PATH. " +
                "Install OpenCode or turn Managed server off and run `opencode serve` yourself."
            )
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["serve", "--hostname", "127.0.0.1", "--port", "\(config.port)"]
        if let nullDevice = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = nullDevice
            process.standardError = nullDevice
        }
        do {
            try process.run()
        } catch {
            throw OpenCodeError.serverUnavailable(
                "Failed to start `opencode serve`: \(error.localizedDescription)"
            )
        }
        managedProcess = process
        openCodeLogger.log("Started managed OpenCode server from \(binaryPath, privacy: .public).")
    }

    public func stopManagedServer() {
        managedProcess?.terminate()
        managedProcess = nil
        sessionsByDirectory.removeAll()
    }

    private func findBinary(named name: String) -> String? {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/sh")
        probe.arguments = ["-c", "command -v \(name)"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do {
            try probe.run()
        } catch {
            return nil
        }
        probe.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    // MARK: Model discovery

    /// Real models from the running server. Never a hardcoded catalog:
    /// an empty or unparseable catalog is an error, not a fallback list.
    public func fetchModels() async throws -> [OpenCodeModel] {
        try await ensureServer()
        let config = OpenCodeConfiguration.load()
        guard let url = endpointURL(config: config, path: "config/providers", directory: nil) else {
            throw OpenCodeError.invalidConfiguration("Invalid OpenCode server URL.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenCodeError.modelUnavailable("OpenCode server returned a non-HTTP response.")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenCodeError.modelUnavailable(
                "OpenCode server returned status \(http.statusCode) for model discovery" +
                (body.isEmpty ? "." : ": \(body.prefix(300))")
            )
        }
        let models = OpenCodeProviderCatalog.parseModels(from: data)
        guard !models.isEmpty else {
            throw OpenCodeError.modelUnavailable(
                "OpenCode server returned no models. Configure a model provider in OpenCode first."
            )
        }
        return models
    }

    // MARK: Streaming prompt

    /// Sends one Assist turn to the server and streams back text deltas.
    ///
    /// - `prompt` is the full Assist turn prompt (task, JSON tool protocol,
    ///   history). It is sent as a text part, exactly as Assist built it.
    /// - `systemPrompt` is SwiftCode's real system prompt (system assets),
    ///   sent in the prompt's `system` field so it — not an OpenCode
    ///   default — governs the turn.
    /// - The session always names the `swiftcode` agent (see
    ///   OpenCodeConfiguration). Tool parts fail the run closed.
    /// - Cancellation aborts the server session.
    public func streamPrompt(
        prompt: String,
        systemPrompt: String?,
        model: OpenCodeModel,
        directory: String?
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await ensureServer()
        let config = OpenCodeConfiguration.load()
        var sessionID = try await session(for: directory)
        do {
            try await promptAsync(sessionID: sessionID, prompt: prompt, systemPrompt: systemPrompt, model: model, config: config, directory: directory)
        } catch let error as OpenCodeError {
            // A stale cached session (server restarted) surfaces as a 404.
            // Drop it and retry exactly once with a fresh session; any
            // other failure propagates unchanged.
            if case .sessionFailed(let detail) = error, detail.contains("status 404") {
                resetSession(directory: directory)
                sessionID = try await session(for: directory)
                try await promptAsync(sessionID: sessionID, prompt: prompt, systemPrompt: systemPrompt, model: model, config: config, directory: directory)
            } else {
                throw error
            }
        }

        guard let eventURL = endpointURL(config: config, path: "event", directory: directory) else {
            throw OpenCodeError.invalidConfiguration("Invalid OpenCode server URL.")
        }
        var request = URLRequest(url: eventURL)
        request.timeoutInterval = 3600
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Precompute the abort request here: the stream's onTermination
        // closure must not capture actor `self` (strict concurrency), so
        // cancellation aborts via this plain URLRequest instead.
        let abortRequest = abortRequest(sessionID: sessionID, config: config, directory: directory)
        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenCodeError.streamInterrupted(
                "OpenCode event stream returned status \(status). The prompt may still be running on the server; abort it from the OpenCode session if needed."
            )
        }

        return AsyncThrowingStream { [bytes, sessionID] continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let event = OpenCodeEvent.parse(line: line) else { continue }
                        if case .parsed(let eventSessionID, let kind) = event {
                            if let eventSessionID, eventSessionID != sessionID { continue }
                            switch kind {
                            case .textDelta(let text):
                                continuation.yield(text)
                            case .tool:
                                continuation.finish(throwing: OpenCodeError.toolExecutionBlocked(
                                    "OpenCode attempted to execute a tool on a SwiftCode session. " +
                                    "Configure the `swiftcode` agent on the server with every permission " +
                                    "denied (see Assist Settings > OpenCode), then retry. The run was aborted."
                                ))
                                return
                            case .idle:
                                continuation.finish()
                                return
                            case .error(let message):
                                continuation.finish(throwing: OpenCodeError.streamInterrupted(message))
                                return
                            case .ignored:
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                if let abortRequest {
                    Task { _ = try? await URLSession.shared.data(for: abortRequest) }
                }
            }
        }
    }

    // MARK: Session plumbing

    private func session(for directory: String?) async throws -> String {
        let key = directory ?? ""
        if let cached = sessionsByDirectory[key] { return cached }
        let config = OpenCodeConfiguration.load()
        guard let url = endpointURL(config: config, path: "session", directory: directory) else {
            throw OpenCodeError.invalidConfiguration("Invalid OpenCode server URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": "SwiftCode Assist"])
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenCodeError.sessionFailed(
                "Failed to create an OpenCode session (status \(status))" +
                (body.isEmpty ? "." : ": \(body.prefix(300))")
            )
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = (json["id"] as? String)
                ?? ((json["data"] as? [String: Any])?["id"] as? String)
                ?? ((json["session"] as? [String: Any])?["id"] as? String),
              !id.isEmpty else {
            throw OpenCodeError.sessionFailed("OpenCode session creation returned no session id.")
        }
        sessionsByDirectory[key] = id
        return id
    }

    private func promptAsync(
        sessionID: String,
        prompt: String,
        systemPrompt: String?,
        model: OpenCodeModel,
        config: OpenCodeConfiguration,
        directory: String?
    ) async throws {
        guard let url = endpointURL(config: config, path: "session/\(sessionID)/prompt_async", directory: directory) else {
            throw OpenCodeError.invalidConfiguration("Invalid OpenCode server URL.")
        }
        var body: [String: Any] = [
            "model": ["providerID": model.providerID, "modelID": model.modelID],
            "agent": config.agentName,
            "parts": [["type": "text", "text": prompt]],
        ]
        if let systemPrompt, !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if status == 404, bodyText.lowercased().contains("agent") {
                throw OpenCodeError.agentNotFound(
                    "OpenCode does not recognise the `\(config.agentName)` agent. " +
                    "Create it on the server (see Assist Settings > OpenCode for the definition) " +
                    "and retry; without it, SwiftCode cannot guarantee its own tool loop."
                )
            }
            throw OpenCodeError.sessionFailed(
                "OpenCode prompt failed (status \(status))" +
                (bodyText.isEmpty ? "." : ": \(bodyText.prefix(300))")
            )
        }
    }

    /// Plain abort request (nonisolated use): built before the stream
    /// exists so cancellation never needs actor state. Returns nil for
    /// an invalid server URL, in which case there is nothing to abort.
    private func abortRequest(sessionID: String, config: OpenCodeConfiguration, directory: String?) -> URLRequest? {
        guard let url = endpointURL(config: config, path: "session/\(sessionID)/abort", directory: directory) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        return request
    }

    // MARK: URL plumbing

    private func endpointURL(config: OpenCodeConfiguration, path: String, directory: String?) -> URL? {
        var components = URLComponents(url: config.serverURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path ?? ""
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        components?.path = trimmedBase + "/" + path
        if let directory, !directory.isEmpty {
            components?.queryItems = [URLQueryItem(name: "directory", value: directory)]
        }
        return components?.url
    }
}
