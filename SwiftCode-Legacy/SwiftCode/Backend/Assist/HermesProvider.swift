import Foundation

public struct HermesModelID: Equatable, Sendable {
    public let spec: String

    public var storedID: String { "hermes:\(spec)" }

    public var provider: String? {
        guard let colon = spec.firstIndex(of: ":") else { return nil }
        let value = String(spec[..<colon])
        return value.isEmpty ? nil : value
    }

    public var model: String {
        guard let colon = spec.firstIndex(of: ":") else { return spec }
        return String(spec[spec.index(after: colon)...])
    }

    public init(spec: String) {
        self.spec = spec
    }

    public static func parse(_ storedID: String) -> HermesModelID? {
        guard storedID.hasPrefix("hermes:") else { return nil }
        let spec = String(storedID.dropFirst("hermes:".count))
        guard !spec.isEmpty else { return nil }
        let parsed = HermesModelID(spec: spec)
        guard !parsed.model.isEmpty else { return nil }
        return parsed
    }

    public static func isHermesModelID(_ storedID: String) -> Bool {
        parse(storedID) != nil
    }
}

public struct HermesConfiguration: Equatable, Sendable {
    public var executablePath: String
    public var toolsets: String
    public var maxTurns: Int

    public init(executablePath: String = "", toolsets: String = "", maxTurns: Int = 0) {
        self.executablePath = executablePath
        self.toolsets = toolsets
        self.maxTurns = maxTurns
    }

    private static let executablePathKey = "hermes.executablePath"
    private static let toolsetsKey = "hermes.toolsets"
    private static let maxTurnsKey = "hermes.maxTurns"

    public static func load() -> HermesConfiguration {
        var config = HermesConfiguration()
        config.executablePath = UserDefaults.standard.string(forKey: executablePathKey) ?? ""
        config.toolsets = UserDefaults.standard.string(forKey: toolsetsKey) ?? ""
        let turns = UserDefaults.standard.integer(forKey: maxTurnsKey)
        config.maxTurns = max(0, turns)
        return config
    }

    public func save() {
        UserDefaults.standard.set(executablePath, forKey: Self.executablePathKey)
        UserDefaults.standard.set(toolsets, forKey: Self.toolsetsKey)
        UserDefaults.standard.set(maxTurns, forKey: Self.maxTurnsKey)
    }

    public var normalisedToolsets: String? {
        let trimmed = toolsets.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum HermesError: Error, LocalizedError, Sendable {
    case executableNotFound(String)
    case invalidModelID(String)
    case launchFailed(String)
    case detectionFailed(String)
    case runFailed(exitCode: Int32, detail: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let detail):
            return "Hermes is not installed or was not found (\(detail)). Install Hermes with the official installer, run `hermes setup` and `hermes model` in a terminal, then set the executable path in Assist Settings → Hermes if it is not on PATH. No other provider was substituted."
        case .invalidModelID(let id):
            return "Invalid Hermes model id \"\(id)\": expected \"hermes:<provider>:<model>\" or \"hermes:<model>\". Select a Hermes model in Assist Settings; SwiftCode never substitutes another model."
        case .launchFailed(let detail):
            return "Failed to launch Hermes: \(detail)"
        case .detectionFailed(let detail):
            return "Could not verify the Hermes installation: \(detail)"
        case .runFailed(let exitCode, let detail):
            return "Hermes run failed (exit \(exitCode)). \(detail)"
        case .cancelled:
            return "Hermes run cancelled."
        }
    }
}

public struct HermesStreamResult: Equatable, Sendable {
    public let sessionId: String?
    public let exitCode: Int
    public let text: String
    public let error: String?

    public init(sessionId: String?, exitCode: Int, text: String, error: String?) {
        self.sessionId = sessionId
        self.exitCode = exitCode
        self.text = text
        self.error = error
    }
}

public enum HermesParsedEvent: Equatable, Sendable {
    case system(sessionId: String?, model: String?)
    case text(String)
    case toolUse(name: String, inputJSON: String)
    case toolResult(name: String, output: String, isError: Bool, durationMs: Double?)
    case result(HermesStreamResult)
    case ignored
}

public enum HermesStreamParser {
    public static func parseLine(_ line: String) -> HermesParsedEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return .ignored
        }
        switch type {
        case "system":
            return .system(
                sessionId: json["session_id"] as? String,
                model: json["model"] as? String
            )
        case "text":
            guard let text = json["text"] as? String else { return .ignored }
            return .text(text)
        case "tool_use":
            guard let name = json["name"] as? String, !name.isEmpty else { return .ignored }
            return .toolUse(name: name, inputJSON: stringify(json["input"]))
        case "tool_result":
            guard let name = json["name"] as? String, !name.isEmpty else { return .ignored }
            let output = (json["output"] as? String) ?? ""
            let isError = (json["is_error"] as? Bool) ?? false
            let duration = (json["duration_ms"] as? NSNumber)?.doubleValue
            return .toolResult(name: name, output: output, isError: isError, durationMs: duration)
        case "result":
            let exitCode = (json["exit_code"] as? NSNumber)?.intValue ?? 1
            let text = (json["text"] as? String) ?? ""
            let error = json["error"] as? String
            return .result(HermesStreamResult(
                sessionId: json["session_id"] as? String,
                exitCode: exitCode,
                text: text,
                error: error
            ))
        default:
            return .ignored
        }
    }

    static func stringify(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }
}

public enum HermesPromptBuilder {
    public static func build(systemPrompt: String, objective: String) -> String {
        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return task }
        guard !task.isEmpty else { return prompt }
        return "\(prompt)\n\n---\n\n\(task)"
    }
}

public struct HermesRunRequest: Sendable {
    public let model: String
    public let systemPrompt: String
    public let userText: String
    public let directory: String
    public let configuration: HermesConfiguration

    public init(
        model: String,
        systemPrompt: String,
        userText: String,
        directory: String,
        configuration: HermesConfiguration = HermesConfiguration.load()
    ) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.userText = userText
        self.directory = directory
        self.configuration = configuration
    }
}

private final class HermesContinuationGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<String, Error>

    init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }

    func resume(with result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(with: result)
    }
}

private final class HermesTimeoutWorkBox: @unchecked Sendable {
    private let lock = NSLock()
    private var workItem: DispatchWorkItem?

    func store(_ item: DispatchWorkItem) {
        lock.lock()
        workItem = item
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let item = workItem
        workItem = nil
        lock.unlock()
        item?.cancel()
    }
}

public actor HermesProvider {
    private var process: Process?
    private var lineContinuation: AsyncStream<String>.Continuation?
    private var cancelled = false
    private var stderrTail = ""

    public private(set) var lastResult: HermesStreamResult?

    public init() {}

    public static var defaultSearchDirectories: [String] {
        var dirs: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        dirs.append("\(home)/.local/bin")
        dirs.append("/opt/homebrew/bin")
        dirs.append("/usr/local/bin")
        return dirs
    }

    public static func resolveExecutable(
        configuredPath: String,
        searchDirectories: [String]
    ) -> String? {
        let fileManager = FileManager.default
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return fileManager.isExecutableFile(atPath: trimmed) ? trimmed : nil
        }
        for dir in searchDirectories {
            let candidate = (dir as NSString).appendingPathComponent("hermes")
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func resolveExecutable(configuration: HermesConfiguration = HermesConfiguration.load()) -> String? {
        resolveExecutable(
            configuredPath: configuration.executablePath,
            searchDirectories: defaultSearchDirectories
        )
    }

    public static func detectVersion(
        executablePath: String? = nil,
        timeout: TimeInterval = 15
    ) async throws -> String {
        let executable = executablePath ?? resolveExecutable()
        guard let executable else {
            throw HermesError.executableNotFound("no `hermes` executable on PATH or in the configured path")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["--version"]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let finish = HermesContinuationGuard(continuation)
            let timeoutBox = HermesTimeoutWorkBox()
            let timeoutWork = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                    finish.resume(with: .failure(HermesError.detectionFailed("hermes --version did not respond within \(Int(timeout))s")))
                }
            }
            timeoutBox.store(timeoutWork)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
            process.terminationHandler = { proc in
                timeoutBox.cancel()
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                let firstLine = out.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if proc.terminationStatus == 0, !firstLine.isEmpty {
                    finish.resume(with: .success(String(firstLine.prefix(200))))
                } else {
                    let detail = SDKToolEvent.redact(err.trimmingCharacters(in: .whitespacesAndNewlines))
                    finish.resume(with: .failure(HermesError.detectionFailed(
                        detail.isEmpty ? "hermes --version exited \(proc.terminationStatus)" : String(detail.prefix(500))
                    )))
                }
            }
            do {
                try process.run()
            } catch {
                timeoutBox.cancel()
                finish.resume(with: .failure(HermesError.launchFailed(error.localizedDescription)))
                return
            }
        }
    }

    public struct HermesDiscoveredModel: Identifiable, Equatable, Sendable {
        public let spec: String
        public var id: String { storedID }
        public var storedID: String { "hermes:\(spec)" }
        public var displayName: String { spec }
        public init(spec: String) { self.spec = spec }
    }

    public static func fetchModels(
        executablePath: String? = nil,
        configuration: HermesConfiguration = HermesConfiguration.load()
    ) async throws -> [HermesDiscoveredModel] {
        let executable = executablePath ?? resolveExecutable(configuration: configuration)
        guard let executable else {
            throw HermesError.executableNotFound("no `hermes` executable on PATH or in the configured path")
        }
        let current = readConfiguredModelSpecs()
        var models = current.map { HermesDiscoveredModel(spec: $0) }
        let openRouterProvider = current.first { $0.hasPrefix("openrouter:") }
        if openRouterProvider != nil {
            if let catalog = try? await OpenRouterAssistProvider.fetchModels() {
                for entry in catalog {
                    let spec = "openrouter:\(entry.id)"
                    if !models.contains(where: { $0.spec == spec }) {
                        models.append(HermesDiscoveredModel(spec: spec))
                    }
                }
            }
        }
        guard !models.isEmpty else {
            throw HermesError.detectionFailed(
                "Could not read a model from `hermes model` output. Run `hermes model` in a terminal to confirm Hermes has a model configured, then try again."
            )
        }
        return models
    }

    public static func readConfiguredModelSpecs(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        let hermesHome = ProcessInfo.processInfo.environment["HERMES_HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? homeDirectory.appendingPathComponent(".hermes", isDirectory: true)
        let configURL = hermesHome.appendingPathComponent("config.yaml")
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return [] }

        var inModelBlock = false
        var provider: String?
        var model: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let isTopLevel = !line.hasPrefix(" ") && !line.hasPrefix("\t")
            if isTopLevel {
                inModelBlock = trimmed == "model:"
                continue
            }
            guard inModelBlock, let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon]
            let value = trimmed[trimmed.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { continue }
            if key == "provider" { provider = value }
            if key == "default" { model = value }
        }
        guard let model else { return [] }
        if let provider {
            return ["\(provider):\(model)"]
        }
        return [model]
    }

    public static func parseModelOutput(_ output: String) -> [String] {
        let tokenPattern = #"([A-Za-z][A-Za-z0-9_-]*):([A-Za-z0-9][A-Za-z0-9._/-]*)"#
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return [] }
        var specs: [String] = []
        func scan(_ text: String) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let providerRange = Range(match.range(at: 1), in: text),
                      let modelRange = Range(match.range(at: 2), in: text) else { continue }
                let provider = String(text[providerRange]).lowercased()
                let model = String(text[modelRange])
                if provider == "https" || provider == "http" { continue }
                if ["session", "id", "error", "code", "provider", "model", "name", "status"].contains(provider) { continue }
                if model.isEmpty || model == "/" { continue }
                let spec = "\(provider):\(model)"
                if !specs.contains(spec) { specs.append(spec) }
            }
        }
        let modelLines = output.split(separator: "\n").filter { $0.lowercased().contains("model") }
        for line in modelLines { scan(String(line)) }
        if specs.isEmpty { scan(output) }
        if specs.isEmpty {
            for line in modelLines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let bare = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                guard !bare.isEmpty, !bare.contains(" "), bare.rangeOfCharacter(from: .alphanumerics) != nil else { continue }
                specs.append(bare)
                break
            }
        }
        return specs
    }

    public static func buildArguments(
        request: HermesRunRequest,
        queryFilePath: String
    ) -> [String] {
        let parsed = HermesModelID.parse(request.model)
        var args: [String] = []
        args += ["--in", request.directory]
        args += ["chat", "--oneshot", "--query-file", queryFilePath, "--format", "stream-json", "--source", "tool"]
        if let provider = parsed?.provider {
            args += ["--provider", provider]
        }
        if let model = parsed?.model, !model.isEmpty {
            args += ["--model", model]
        }
        if let toolsets = request.configuration.normalisedToolsets {
            args += ["--toolsets", toolsets]
        }
        if request.configuration.maxTurns > 0 {
            args += ["--max-turns", String(request.configuration.maxTurns)]
        }
        return args
    }

    public func run(
        _ request: HermesRunRequest,
        onToolEvent: @escaping @Sendable (SDKToolEvent) -> Void
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.execute(request, continuation: continuation, onToolEvent: onToolEvent)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func cancel() {
        cancelled = true
        lineContinuation?.finish()
        guard let process, process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            #if canImport(Darwin)
            if Darwin.kill(pid, 0) == 0 {
                Darwin.kill(pid, SIGKILL)
            }
            #endif
        }
    }

    private func execute(
        _ request: HermesRunRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        onToolEvent: @escaping @Sendable (SDKToolEvent) -> Void
    ) async throws {
        guard !cancelled else {
            throw HermesError.cancelled
        }
        guard HermesModelID.parse(request.model) != nil else {
            throw HermesError.invalidModelID(request.model)
        }
        guard let executable = Self.resolveExecutable(configuration: request.configuration) else {
            throw HermesError.executableNotFound(
                request.configuration.executablePath.isEmpty
                    ? "no `hermes` executable on PATH or in ~/.local/bin"
                    : "configured path \"\(request.configuration.executablePath)\" is not executable"
            )
        }

        let queryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftcode-hermes-query-\(UUID().uuidString).txt")
        let payload = HermesPromptBuilder.build(systemPrompt: request.systemPrompt, objective: request.userText)
        do {
            try payload.write(to: queryFile, atomically: true, encoding: .utf8)
        } catch {
            throw HermesError.launchFailed("Could not write the Hermes query file: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: queryFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Self.buildArguments(request: request, queryFilePath: queryFile.path)
        process.currentDirectoryURL = URL(fileURLWithPath: request.directory)
        var environment: [String: String] = [:]
        let parent = ProcessInfo.processInfo.environment
        var pathValue = parent["PATH"] ?? ""
        let binDir = (executable as NSString).deletingLastPathComponent
        pathValue = pathValue.isEmpty ? binDir : "\(binDir):\(pathValue)"
        environment["PATH"] = pathValue
        if let home = parent["HOME"] { environment["HOME"] = home }
        if let tmp = parent["TMPDIR"] { environment["TMPDIR"] = tmp }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.process = process
        self.lastResult = nil
        self.stderrTail = ""

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await self?.appendStderr(text) }
        }

        let (lineStream, lineContinuation) = AsyncStream<String>.makeStream()
        self.lineContinuation = lineContinuation
        let buffer = BufferWrapper()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            while let newline = buffer.popLine() {
                if let line = String(data: newline, encoding: .utf8), !line.isEmpty {
                    lineContinuation.yield(line)
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }
        do {
            try process.run()
        } catch {
            throw HermesError.launchFailed(error.localizedDescription)
        }
        if cancelled {
            process.terminate()
            throw HermesError.cancelled
        }

        let runToken = String(UUID().uuidString.prefix(8))
        var toolCallCounter = 0
        var pendingByName: [String: [String]] = [:]
        for await line in lineStream {
            switch HermesStreamParser.parseLine(line) {
            case .text(let delta):
                guard !delta.isEmpty else { continue }
                continuation.yield(delta)
            case .toolUse(let name, let inputJSON):
                toolCallCounter += 1
                let callId = "hermes-\(runToken)-\(name)-\(toolCallCounter)"
                pendingByName[name, default: []].append(callId)
                onToolEvent(SDKToolEvent(
                    provider: "hermes",
                    sessionId: "",
                    toolCallId: callId,
                    toolName: name,
                    source: .hermes,
                    state: .running,
                    arguments: inputJSON
                ))
            case .toolResult(let name, let output, let isError, _):
                let callId: String
                if var queue = pendingByName[name], !queue.isEmpty {
                    callId = queue.removeFirst()
                    pendingByName[name] = queue
                } else {
                    toolCallCounter += 1
                    callId = "hermes-\(runToken)-\(name)-\(toolCallCounter)"
                }
                onToolEvent(SDKToolEvent(
                    provider: "hermes",
                    sessionId: "",
                    toolCallId: callId,
                    toolName: name,
                    source: .hermes,
                    state: isError ? .failed : .completed,
                    result: isError ? nil : output,
                    error: isError ? (output.isEmpty ? "Hermes tool failed" : output) : nil,
                    completedAt: Date()
                ))
            case .result(let result):
                self.lastResult = result
            case .system, .ignored:
                continue
            }
        }

        if cancelled {
            throw HermesError.cancelled
        }
        if let result = lastResult {
            if result.exitCode != 0 {
                let detail = result.error.map { SDKToolEvent.redact($0) } ?? ""
                let tail = SDKToolEvent.redact(stderrTail).trimmingCharacters(in: .whitespacesAndNewlines)
                let combined = [detail, tail].filter { !$0.isEmpty }.joined(separator: " ")
                throw HermesError.runFailed(
                    exitCode: Int32(result.exitCode),
                    detail: combined.isEmpty
                        ? "Hermes reported failure with no further detail; check Hermes configuration with `hermes doctor`."
                        : String(combined.prefix(1000))
                )
            }
            continuation.finish()
            return
        }
        let exitCode = process.terminationStatus
        if exitCode != 0 {
            let tail = SDKToolEvent.redact(stderrTail).trimmingCharacters(in: .whitespacesAndNewlines)
            throw HermesError.runFailed(
                exitCode: exitCode,
                detail: tail.isEmpty
                    ? "Hermes exited without a result record; check Hermes configuration with `hermes doctor`."
                    : String(tail.prefix(1000))
            )
        }
        continuation.finish()
    }

    private func appendStderr(_ text: String) {
        stderrTail += text
        if stderrTail.count > 8192 {
            stderrTail = String(stderrTail.suffix(8192))
        }
    }

    private func handleTermination() {
        lineContinuation?.finish()
        lineContinuation = nil
    }
}
