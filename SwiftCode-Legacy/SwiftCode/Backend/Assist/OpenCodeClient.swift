import Foundation
import os

private let openCodeLogger = Logger(subsystem: "com.swiftcode.app", category: "OpenCodeClient")

private final class OpenCodeInstallGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<Bool, Never>
    private var timeoutWork: DispatchWorkItem?

    init(continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    func setTimeoutWork(_ work: DispatchWorkItem) {
        lock.lock()
        defer { lock.unlock() }
        timeoutWork = work
    }

    func resume(with value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        timeoutWork?.cancel()
        continuation.resume(returning: value)
    }
}

public enum OpenCodeError: LocalizedError, Equatable {
    case serverUnavailable(String)
    case invalidConfiguration(String)
    case sessionFailed(String)
    case modelUnavailable(String)
    case streamInterrupted(String)
    case agentNotFound(String)
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
            return .parsed(sessionID: sessionID, kind: .ignored)
        }
        return .parsed(sessionID: sessionID, kind: .ignored)
    }
}

public actor OpenCodeClient {
    public static let shared = OpenCodeClient()

    private var sessionsByDirectory: [String: String] = [:]
    private var managedProcess: Process?
    private let urlSession = URLSession(configuration: .default)

    private init() {}

    public func configuration() -> OpenCodeConfiguration {
        OpenCodeConfiguration.load()
    }

    public func resetSession(directory: String?) {
        sessionsByDirectory.removeValue(forKey: directory ?? "")
    }

    public func resetAllSessions() {
        sessionsByDirectory.removeAll()
    }

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

    public func ensureServer() async throws {
        if await checkHealth() { return }
        let config = OpenCodeConfiguration.load()
        guard config.isLoopback else {
            throw OpenCodeError.serverUnavailable(
                "OpenCode server at \(config.serverURL.absoluteString) is not reachable, and SwiftCode only auto-starts loopback servers. Point the server URL at 127.0.0.1 in Assist Settings → OpenCode, or run your own server at that URL."
            )
        }
        try await startManagedServer(config: config)
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { break }
            if await checkHealth() { return }
        }
        throw OpenCodeError.serverUnavailable(
            "SwiftCode started an OpenCode server, but it did not become healthy at " +
            "\(config.serverURL.absoluteString) within 30 seconds. The port may be in use by another process."
        )
    }

    public func startManagedServer(config: OpenCodeConfiguration? = nil) async throws {
        let config = config ?? OpenCodeConfiguration.load()
        guard config.isLoopback else {
            throw OpenCodeError.invalidConfiguration(
                "Managed OpenCode server startup is only supported for loopback URLs."
            )
        }
        if let process = managedProcess, process.isRunning { return }
        ensureSwiftCodeAgentDefinition()
        var binaryPath = findBinary(named: "opencode")
        if binaryPath == nil {
            binaryPath = await autoInstallOpenCodeBinary()
            if binaryPath == nil {
                binaryPath = findBinary(named: "opencode")
            }
        }
        guard let binaryPath else {
            throw OpenCodeError.serverUnavailable(
                "SwiftCode could not find an `opencode` binary and could not install one automatically (no npm or bun was found, or the install failed). Install Node.js, then try again — SwiftCode will pick the binary up automatically."
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
        }
        probe.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(name)",
            "\(home)/.npm-global/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/homebrew/lib/node_modules/opencode-ai/bin/\(name)",
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func autoInstallOpenCodeBinary() async -> String? {
        for installer in ["npm", "bun"] {
            guard let installerPath = findBinary(named: installer) else { continue }
            let args = installer == "npm"
                ? ["install", "-g", "opencode-ai"]
                : ["install", "-g", "opencode-ai"]
            let installed = await runInstallCommand(executable: installerPath, arguments: args, timeoutSeconds: 180)
            if installed {
                return findBinary(named: "opencode")
            }
        }
        return nil
    }

    private func runInstallCommand(executable: String, arguments: [String], timeoutSeconds: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
            process.standardError = FileHandle(forWritingAtPath: "/dev/null")
            let guardBox = OpenCodeInstallGuard(continuation: continuation)
            let timeoutWork = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                    guardBox.resume(with: false)
                }
            }
            guardBox.setTimeoutWork(timeoutWork)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)
            process.terminationHandler = { proc in
                guardBox.resume(with: proc.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                guardBox.resume(with: false)
            }
        }
    }

    private func ensureSwiftCodeAgentDefinition() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let agentDir = home.appendingPathComponent(".config/opencode/agent", isDirectory: true)
        let agentFile = agentDir.appendingPathComponent("swiftcode.md")
        guard !FileManager.default.fileExists(atPath: agentFile.path) else { return }
        do {
            try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
            try OpenCodeConfiguration.swiftcodeAgentDefinition.write(to: agentFile, atomically: true, encoding: .utf8)
            openCodeLogger.log("Wrote missing OpenCode swiftcode agent definition to ~/.config/opencode/agent/swiftcode.md.")
        } catch {
            openCodeLogger.error("Could not write OpenCode swiftcode agent definition: \(error.localizedDescription, privacy: .public)")
        }
    }

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

    public func streamPrompt(
        prompt: String,
        systemPrompt: String?,
        model: OpenCodeModel,
        directory: String?
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await ensureServer()
        let config = OpenCodeConfiguration.load()
        var sessionID = try await session(for: directory)
        var bytes = try await openEventStream(config: config, directory: directory)
        do {
            try await promptAsync(sessionID: sessionID, prompt: prompt, systemPrompt: systemPrompt, model: model, config: config, directory: directory)
        } catch let error as OpenCodeError {
            if case .sessionFailed(let detail) = error, detail.contains("status 404") {
                resetSession(directory: directory)
                sessionID = try await session(for: directory)
                bytes = try await openEventStream(config: config, directory: directory)
                try await promptAsync(sessionID: sessionID, prompt: prompt, systemPrompt: systemPrompt, model: model, config: config, directory: directory)
            } else {
                throw error
            }
        }

        let abortRequest = abortRequest(sessionID: sessionID, config: config, directory: directory)

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

    private func openEventStream(config: OpenCodeConfiguration, directory: String?) async throws -> URLSession.AsyncBytes {
        guard let eventURL = endpointURL(config: config, path: "event", directory: directory) else {
            throw OpenCodeError.invalidConfiguration("Invalid OpenCode server URL.")
        }
        var request = URLRequest(url: eventURL)
        request.timeoutInterval = 3600
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenCodeError.streamInterrupted(
                "OpenCode event stream returned status \(status). The prompt may still be running on the server; abort it from the OpenCode session if needed."
            )
        }
        return bytes
    }

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

    private func abortRequest(sessionID: String, config: OpenCodeConfiguration, directory: String?) -> URLRequest? {
        guard let url = endpointURL(config: config, path: "session/\(sessionID)/abort", directory: directory) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        return request
    }

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
