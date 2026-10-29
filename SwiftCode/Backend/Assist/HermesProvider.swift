import Foundation

// MARK: - Hermes Agent provider (SwiftCode Assist)
//
// Hermes Agent by Nous Research is a Python CLI agent, not a Swift
// library and not a JS SDK. There is therefore no SDK bridge to host
// (unlike OpenCode / OpenRouter in SDKRuntimeManager): SwiftCode
// launches the real `hermes` executable as a child process and talks
// to it through its documented programmatic interface:
//
//   hermes --in <workspace> chat --oneshot --query-file <file>
//          --format stream-json --source tool
//          [--provider <provider>] [--model <model>]
//          [--toolsets <csv>] [--max-turns <n>]
//
// Verified against the Hermes Agent repository
// (https://github.com/NousResearch/hermes-agent) and its CLI reference
// (`website/docs/reference/cli-commands.md` in that repo):
//
// * `chat --oneshot` with `-q` / `--query-file` answers and exits, so
//   one SwiftCode task maps to one bounded Hermes run. A fresh run is
//   used for every task: SwiftCode never passes `--resume`, so Hermes
//   session state is never silently carried across SwiftCode tasks.
// * `--format stream-json` emits one JSON object per stdout line:
//   `system` (init: model, session_id), `text` (assistant delta),
//   `tool_use` (name, input), `tool_result` (name, output capped at
//   5000 chars, duration_ms, is_error), and a terminal `result`
//   (session_id, exit_code, text = the whole reply, tokens,
//   duration_ms, error). Diagnostics stay on stderr.
// * Exit codes for finite runs: 0 completed, 1 failed / partial /
//   iteration budget / never ran, 130 interrupted, 75 transient
//   provider failure (dispatcher requeue code; surfaced here as a
//   failure, never retried silently).
//
// Deliberately NOT used:
//
// * `hermes -z` — the scripted one-shot. It prints final text only
//   (no tool events, so tool activity could not be shown) and, worse,
//   it sets HERMES_YOLO_MODE=1 internally (hermes_cli/oneshot.py:
//   "Non-interactive by definition — an approval prompt would hang
//   forever"). SwiftCode must never silently auto-approve.
// * `hermes acp` — the ACP server. It is a real editor protocol, but
//   implementing a full ACP JSON-RPC host (permission callbacks,
//   session lifecycle, gateway viewer semantics) would be a larger,
//   riskier surface for no capability gain over stream-json, and ACP
//   likewise cannot inject SwiftCode's system prompt.
// * `@hermes/plugin-sdk` — the Hermes Desktop plugin SDK. It extends
//   Hermes Desktop's UI; it is not an agent-execution interface and
//   is never imported or built here.
//
// Approvals (important, stated plainly in Settings too): a
// single-query (`-q`) Hermes run has no user at a terminal to answer
// an approval prompt, so Hermes' own `approvals.single_query_mode`
// applies — its default is `deny`, i.e. a dangerous command is
// blocked and the agent must find another way. SwiftCode never passes
// `--yolo` and never sets HERMES_YOLO_MODE / HERMES_ACCEPT_HOOKS, and
// it launches Hermes with a controlled environment (PATH/HOME/TMPDIR
// only) so a stray HERMES_* variable in the parent environment can
// never change that. Hermes tools therefore always run under Hermes'
// own approval policy, never under SwiftCode's tool permissions —
// and the Settings text says so. If the user's Hermes config sets
// single_query_mode to `approve`, that is their Hermes configuration
// choice, not something SwiftCode enables.
//
// SwiftCode-native tools: the stream-json interface is observational
// for tools — Hermes reports the tools IT executes; there is no
// documented callback by which SwiftCode could execute its own
// registry tools inside a Hermes run. This provider therefore sends
// NO SwiftCode tool schemas to Hermes and never claims SwiftCode
// tools ran. Tool events are published to SDKToolEventStore with
// source `.hermes` so HermesToolsUIView renders exactly what Hermes
// did. SwiftCode native tools remain available on every other
// provider; selecting Hermes is an explicit choice of Hermes' tool
// system (see Docs/Assist-Hermes-Provider.md).
//
// System prompt: Hermes' chat parser has no --system-prompt flag.
// SwiftCode's assembled prompt (base instructions + retrieved System
// Asset instructions, built by AssistSDKSessionRunner's shared
// helper) is delivered as the first part of the query file, followed
// by the task. That is user-turn delivery, not a Hermes system
// prompt, and Hermes' own profile SOUL.md / workspace rules still
// apply on top — the Settings text and the doc say so rather than
// claiming the prompt replaced them. SwiftCode never writes to
// ~/.hermes/SOUL.md, config.yaml, or .env to force its prompt in.
//
// Secrets: Hermes credentials live in Hermes' own ~/.hermes/.env and
// config.yaml. SwiftCode stores no Hermes API key, never passes
// --api-key / --base-url (which would put a key in argv and in
// Hermes' launch-only memory), and redacts tool arguments/results
// and stderr tails through SDKToolEvent.redact before they reach
// the UI or an error string.

// MARK: - Model identity

/// A model selected through the Hermes provider.
///
/// Stored in `selectedAssistModelID` as `hermes:<spec>` where `<spec>`
/// is Hermes' own model syntax: either `provider:model` (for example
/// `hermes:openrouter:anthropic/claude-sonnet-4-6`) or a bare model
/// name Hermes resolves against its configured default provider
/// (for example `hermes:gpt-5.5`). The `hermes:` prefix is deliberate:
/// a bare `provider/model` id already routes to OpenRouter in
/// LLMService, so an unprefixed Hermes model would be silently sent
/// to the wrong provider. Nothing here ever strips the prefix and
/// re-routes the model elsewhere.
public struct HermesModelID: Equatable, Sendable {
    /// The Hermes model spec after the `hermes:` prefix.
    public let spec: String

    public var storedID: String { "hermes:\(spec)" }

    /// The Hermes provider override, when the spec carries one
    /// (`provider:model`). Nil for a bare model name: Hermes then
    /// uses its configured default provider and SwiftCode must not
    /// invent one.
    public var provider: String? {
        guard let colon = spec.firstIndex(of: ":") else { return nil }
        let value = String(spec[..<colon])
        return value.isEmpty ? nil : value
    }

    /// The model name Hermes receives via --model: the part after the
    /// provider prefix, or the whole spec for a bare model name.
    public var model: String {
        guard let colon = spec.firstIndex(of: ":") else { return spec }
        return String(spec[spec.index(after: colon)...])
    }

    public init(spec: String) {
        self.spec = spec
    }

    /// Parses a stored `hermes:` model identifier. Returns nil for any
    /// other provider's identifier, for an empty spec, and for a spec
    /// whose model part is empty (`hermes:openrouter:`).
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

// MARK: - Configuration

/// Persisted Hermes settings. Only the settings the stream-json
/// interface actually consumes: the executable to launch, the
/// optional toolset restriction, and the optional iteration budget.
/// Model selection lives in the selected model id (HermesModelID),
/// provider selection in `assist.selectedProvider` — neither is
/// duplicated here, so switching providers can never desync them.
public struct HermesConfiguration: Equatable, Sendable {
    /// Explicit `hermes` executable path. Empty means auto-detect:
    /// PATH plus the well-known install locations (see
    /// HermesProvider.resolveExecutable).
    public var executablePath: String
    /// Optional comma-separated toolsets passed as `--toolsets`
    /// (for example `file,web`). Empty means Hermes' defaults.
    /// Narrowing this is how a user removes terminal / code execution
    /// from a Hermes run; see Docs/Assist-Hermes-Provider.md.
    public var toolsets: String
    /// Optional `--max-turns` iteration budget. 0 means Hermes'
    /// default (500, or `agent.max_turns` in Hermes config).
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

    /// Normalised toolsets for argv, or nil when Hermes' defaults
    /// should apply. Whitespace-only input is treated as empty so a
    /// stray space can never be passed as a toolset name.
    public var normalisedToolsets: String? {
        let trimmed = toolsets.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Errors

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

// MARK: - Stream-json events

/// The terminal `result` record of a stream-json run, as documented
/// by Hermes. Read from the provider after its text stream finishes;
/// it is authoritative for the final text (text deltas can stop early
/// on a replay gap, while `result.text` is the whole reply).
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

/// One parsed stream-json line. `tool_use` / `tool_result` records
/// carry no call id on the wire (see the header note), so the
/// provider synthesises stable ids when publishing tool events.
public enum HermesParsedEvent: Equatable, Sendable {
    case system(sessionId: String?, model: String?)
    case text(String)
    case toolUse(name: String, inputJSON: String)
    case toolResult(name: String, output: String, isError: Bool, durationMs: Double?)
    case result(HermesStreamResult)
    /// A well-formed line of a type SwiftCode does not act on, or a
    /// malformed line. Never crashes a run and never invents data.
    case ignored
}

public enum HermesStreamParser {
    /// Parses one stream-json stdout line. Returns `.ignored` for
    /// blank lines, malformed JSON, and event types SwiftCode does
    /// not consume — a single bad line must never abort a run.
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

    /// Renders a tool `input` value as compact JSON (or a plain
    /// string when it already is one). Nil input renders as "".
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

// MARK: - Prompt delivery

public enum HermesPromptBuilder {
    /// Builds the query-file payload: SwiftCode's assembled system
    /// prompt, then the task, separated so the task cannot silently
    /// merge into the instructions. This is delivered as the user
    /// turn (Hermes has no --system-prompt flag); the header comment
    /// in this file and the Settings text state that limit.
    public static func build(systemPrompt: String, objective: String) -> String {
        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return task }
        guard !task.isEmpty else { return prompt }
        return "\(prompt)\n\n---\n\n\(task)"
    }
}

// MARK: - Run request

public struct HermesRunRequest: Sendable {
    /// Stored model id (`hermes:...`). Validated with HermesModelID
    /// before launch; never guessed or rewritten.
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

// MARK: - Provider

/// One-shot continuation guard for `detectVersion`: the termination
/// handler and the timeout task race, so the exactly-once resume
/// must be locked rather than a shared mutable flag (Swift 6 would
/// reject the flag as concurrently mutated).
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

/// Holds the `detectVersion` timeout work item so the @Sendable
/// termination handler can cancel it without capturing the
/// non-Sendable DispatchWorkItem directly.
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

/// Swift facade for Hermes stream-json runs. One provider instance
/// serves one run at a time; `cancel()` terminates the child process
/// it owns (SIGTERM, a grace wait, then SIGKILL) and never touches
/// any other process. The provider executes no SwiftCode tools and
/// accepts no tool executor: Hermes tools are observed, not bridged.
public actor HermesProvider {
    private var process: Process?
    private var lineContinuation: AsyncStream<String>.Continuation?
    private var cancelled = false
    private var stderrTail = ""

    /// The terminal `result` record, when one arrived. Nil when the
    /// process exited without a result record (crash, signal, or a
    /// stream cut short) — the runner then judges the run by the
    /// process exit code and the accumulated text, never by inventing
    /// a result.
    public private(set) var lastResult: HermesStreamResult?

    public init() {}

    // MARK: Executable discovery

    /// Well-known Hermes install locations, after PATH. Recent
    /// installs write launchers into ~/.local/bin; the official
    /// installer also uses a checkout venv (not guessed here — a
    /// checkout install is found through its ~/.local/bin launcher
    /// or an explicit path in Settings).
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

    /// Returns the first executable named `hermes` in the given
    /// directories, or nil. Pure over its inputs, so tests can pass
    /// synthetic directories instead of depending on the host PATH.
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

    /// Runs `hermes --version` and returns its first stdout line, or
    /// throws. Used by Settings status checks; never used to gate a
    /// run (a run re-resolves and re-validates its executable).
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
            // Timeout via DispatchWorkItem, not a Task: a Task's
            // @Sendable closure cannot capture the non-Sendable
            // Process under strict Swift 6 concurrency.
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

    // MARK: Argument construction

    /// Builds the argv for one run (excluding the executable itself).
    /// Pure over its inputs so tests can assert the exact invocation
    /// without launching anything. Never includes a secret, a prompt,
    /// or a model key: the prompt travels in the query file, never
    /// argv, so it cannot leak into a process listing.
    public static func buildArguments(
        request: HermesRunRequest,
        queryFilePath: String
    ) -> [String] {
        // HermesModelID.parse is validated by the caller; fall back to
        // the raw spec here only so this pure function stays total —
        // a run with an invalid id is rejected before launch.
        let parsed = HermesModelID.parse(request.model)
        var args: [String] = []
        // --in is a global option: it must precede the subcommand.
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

    // MARK: Run

    /// Runs one request, streaming assistant text deltas. Tool
    /// activity is reported through `onToolEvent` as SDKToolEvents
    /// (provider "hermes", source `.hermes`); the terminal `result`
    /// record is available as `lastResult` after the stream ends.
    /// A failure with no result record finishes the stream throwing.
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

    /// Terminates the CLI child process SwiftCode started. This does
    /// NOT guarantee the gateway turn stops: modern `hermes chat` is
    /// a gateway client, and Hermes documents that accepted work
    /// continues at the gateway after detach. No CLI command exists
    /// to cancel a gateway turn from outside (that would need ACP
    /// `session/cancel`); see Docs/Assist-Hermes-Provider.md.
    public func cancel() {
        cancelled = true
        lineContinuation?.finish()
        guard let process, process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        // pid-only grace wait: a Task's @Sendable closure cannot
        // capture the non-Sendable Process under strict Swift 6,
        // and kill(pid, 0) is the equivalent liveness check.
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
        // A cancel that arrived before execution started must not be
        // cleared by the reset below: fail before launching anything.
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

        // The prompt goes in a temp file, not argv: --query-file is
        // documented to pass the body verbatim (no shell
        // interpretation of quotes, $(), or backticks), and a temp
        // file outside the workspace can never pollute the project
        // or appear in a process listing. Deleted in `defer` on every
        // exit path, including cancellation.
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
        // Controlled environment: PATH (with the executable's dir
        // first), HOME, TMPDIR only. In particular no HERMES_*
        // variable is inherited, so a stray HERMES_YOLO_MODE in the
        // parent environment can never auto-approve a Hermes run.
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
        // Deliberately NOT reset here: a cancel that arrived during
        // validation or the query-file write must survive to the
        // post-launch check below. Each run uses a fresh provider,
        // so no stale flag can leak from a previous run.
        self.stderrTail = ""

        // Drain stderr into a capped, redacted tail (never /dev/null:
        // a Hermes import failure would otherwise surface as a
        // generic error; never unbounded: a chatty child must not
        // grow memory without limit).
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

        // Tool-call ids are synthesised (the wire carries none) and
        // must be unique per run: the store merges by toolCallId +
        // source within a session, and a second task in the same
        // session reusing "hermes-read_file-1" would otherwise fuse
        // into the first task's row. The run token prevents that.
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

        // The line stream ends on process exit (see
        // handleTermination) or on cancel(). Judge the run by the
        // terminal record first, then by the exit code — never by
        // whether any text arrived.
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
