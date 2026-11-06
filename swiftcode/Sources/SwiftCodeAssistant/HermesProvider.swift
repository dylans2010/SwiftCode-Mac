import Foundation
import SwiftCodeSubprocess

/// Hermes Agent (Nous Research) as a coding-assistant back end.
///
/// CORRECTION TO THE BRIEF: Legacy does NOT speak ACP. Its header and
/// implementation were verified live (`SwiftCode/Backend/Assist/
/// HermesProvider.swift`, Legacy @ d51a8f0d): Hermes is a Python CLI
/// agent launched as a child process and driven through its documented
/// `chat --oneshot --format stream-json` interface:
///
///   hermes --in <workspace> chat --oneshot --query-file <file>
///          --format stream-json --source tool
///          [--provider <provider>] [--model <model>]
///          [--toolsets <csv>] [--max-turns <n>]
///
/// Legacy deliberately rejected `hermes acp` (a full ACP JSON-RPC host
/// — permission callbacks, session lifecycle, gateway viewer semantics
/// — would be a larger, riskier surface for no capability gain, and ACP
/// likewise cannot inject SwiftCode's system prompt). This provider
/// therefore does NOT use the host's `ACPConnection`/`ACPClient`: that
/// client speaks ACP version 1 over stdin/stdout JSON-RPC, which is
/// not the protocol Hermes is driven with here. No second ACP stack is
/// built either — there is no ACP code in this file at all. Instead the
/// provider follows the host's other CLI-agent pattern
/// (`CLIAgentProvider` + `StreamingSubprocess.lines`): one real child
/// process per request, its stdout streamed as JSON lines.
///
/// One-shot semantics (from `HermesSessionRunner.swift`, 121 lines):
/// one SwiftCode task maps to one bounded Hermes run. A fresh run is
/// used for every task — never `--resume` — so Hermes session state is
/// never silently carried across tasks. Hermes runs its own tools and
/// SwiftCode only observes them: NO SwiftCode tool schemas are sent to Hermes
/// (there is no documented callback by which SwiftCode tools could execute
/// inside a Hermes run), and Hermes tool events surface as
/// `.activity` lines. Cancellation stops the local child process
/// (via `StreamingSubprocess`'s escalating SIGINT → SIGTERM → SIGKILL);
/// Legacy documents that a gateway turn already accepted by Hermes may
/// continue after detach — SwiftCode stops watching, it cannot guarantee
/// Hermes stopped working.
///
/// Approvals: a single-query Hermes run has no user at a terminal, so
/// Hermes' own `approvals.single_query_mode` applies (default `deny`).
/// This provider never passes `--yolo` and never sets
/// `HERMES_YOLO_MODE` / `HERMES_ACCEPT_HOOKS`, and launches Hermes
/// with a controlled environment (PATH/HOME/TMPDIR only, plus the
/// credential variable below) so a stray `HERMES_*` variable in the
/// parent environment can never change that. Hermes tools therefore
/// run under Hermes' own approval policy, never under SwiftCode's.
///
/// Credentials — SwiftCode deviation from Legacy, recorded in the spec:
/// Legacy stores no Hermes key and Hermes reads its own
/// Hermes' own credential file, which SwiftCode never reads or writes
/// (see §3.5).
/// Instead, when the selected model's provider has a documented key
/// variable (`OPENROUTER_API_KEY`, `OPENAI_API_KEY` — Hermes' public
/// environment-variable reference), the key is read from SwiftCode's
/// `SecretStore` (Keychain on macOS) and placed in the child
/// process's environment at spawn time. Providers with no documented
/// mapping keep Legacy behaviour: Hermes authenticates itself from
/// its own `.env` via HOME. The key is never put in argv, never
/// logged, and error text is passed through `redacted(_:secrets:)`.
/// See specs/ide/assist-providers-hermes.md.
public struct HermesProvider: AssistantProvider {
    public var kind: ProviderKind { .hermes }

    /// The located `hermes` executable (nil: not installed).
    public var executable: URL?
    /// Launch options (toolsets, iteration budget, explicit path).
    public var configuration: HermesConfiguration
    /// Where API keys live. Nil: Hermes authenticates itself from its
    /// own configuration, exactly as in Legacy.
    public var secretStore: (any SecretStore)?
    /// Home directory used to read Hermes' configured model (see
    /// `readConfiguredModelSpecs`). Tests point this at a fixture.
    public var homeDirectory: URL

    public init(executable: URL?, configuration: HermesConfiguration = HermesConfiguration(),
                secretStore: (any SecretStore)? = nil,
                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.executable = executable
        self.configuration = configuration
        self.secretStore = secretStore
        self.homeDirectory = homeDirectory
    }

    /// Locates `hermes` like the other CLI agents (PATH, then the
    /// usual install folders), honouring an explicit path in the
    /// configuration.
    public init(locator: CLIToolLocator = CLIToolLocator(),
                configuration: HermesConfiguration = HermesConfiguration(),
                secretStore: (any SecretStore)? = nil,
                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(executable: locator.find("hermes",
                                           override: configuration.executablePath.isEmpty ? nil : configuration.executablePath),
                  configuration: configuration, secretStore: secretStore, homeDirectory: homeDirectory)
    }

    public static let setupHint =
        "Hermes was not found. Install Hermes and sign in once by running `hermes setup` and `hermes model` in Terminal, then try again."

    // MARK: - Availability and models

    /// Binary absent → `.notInstalled`. Binary present → the models
    /// Hermes itself reports: its configured model, read from its
    /// `config.yaml` (model fields only — never secrets, never
    /// `.env`), as `hermes:<spec>` ids. When no model is configured,
    /// a single `Default` entry: the agent runs with whatever model
    /// Hermes itself defaults to. There is no hardcoded model list
    /// anywhere here; Hermes exposes no model-list command.
    public func availability() async -> ProviderAvailability {
        guard executable != nil else { return .notInstalled(hint: Self.setupHint) }
        let specs = Self.readConfiguredModelSpecs(homeDirectory: homeDirectory)
        if !specs.isEmpty {
            return .ready(specs.map { ModelInfo(id: "hermes:\($0)", displayName: $0) })
        }
        return .ready([ModelInfo(id: "", displayName: "Default")])
    }

    /// Hermes reports no context window for its models.
    public func contextWindow(model: String) async -> Int? { nil }

    // MARK: - One-shot run

    public func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let provider = self
        return eventStream { out in
            guard let exe = provider.executable else {
                throw AssistantError.tool(name: "Hermes", message: Self.setupHint)
            }
            let dir = request.workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            let modelID = try provider.resolvedModelID(request.model)

            // The prompt goes in a temp file, not argv: `--query-file`
            // passes the body verbatim (no shell interpretation of
            // quotes, $(), or backticks), and a temp file outside the
            // workspace can never pollute the project or appear in a
            // process listing. Deleted in `defer` on every exit path,
            // including cancellation.
            let queryFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-hermes-query-\(UUID().uuidString).txt")
            let payload = HermesPromptBuilder.build(systemPrompt: request.instructions,
                                                   objective: provider.objectiveText(request))
            do {
                try payload.write(to: queryFile, atomically: true, encoding: .utf8)
            } catch {
                throw AssistantError.tool(name: "Hermes", message: "Could not write the Hermes query file: \(error.localizedDescription)")
            }
            defer { try? FileManager.default.removeItem(at: queryFile) }

            let apiKeyVariable = Self.credentialEnvironmentVariable(forProvider: modelID?.provider)
            let apiKey = apiKeyVariable.flatMap { _ in
                provider.secretStore?.readString(Self.apiKeyAccount(forProvider: modelID?.provider) ?? "")
            }
            let environment = Self.environment(executable: exe, apiKey: apiKey, apiKeyVariable: apiKeyVariable)
            let args = Self.buildArguments(model: modelID, directory: dir.path,
                                           queryFilePath: queryFile.path, configuration: provider.configuration)
            var parser = HermesStreamEventParser()
            var finished = false
            do {
                for try await line in StreamingSubprocess.lines(exe, args, environment: environment, currentDirectory: dir) {
                    for event in try parser.parse(line) {
                        out.yield(event)
                        if case .finished = event { finished = true }
                    }
                }
            } catch let e as StreamingSubprocess.ExitError {
                if e.wasInterrupted { throw CancellationError() }
                if parser.terminalResult?.exitCode == 0 {
                    // The process died after a successful terminal
                    // result; honour the result below.
                } else {
                    throw AssistantError.tool(name: "Hermes", message: Self.explain(status: e.status, stderrTail: e.stderrTail, secrets: [apiKey].compactMap { $0 }))
                }
            }
            try Task.checkCancellation()
            for event in parser.finish() {
                out.yield(event)
                if case .finished = event { finished = true }
            }
            if !finished {
                guard parser.sawText || parser.terminalResult != nil else {
                    throw AssistantError.tool(name: "Hermes", message: "Hermes completed without a final response.")
                }
                out.yield(.finished(parser.terminalResult?.tokens))
            }
        }
    }

    /// The task text for the query file: the conversation so far
    /// (earlier turns as `<role>` blocks) followed by the new message.
    /// `HermesPromptBuilder` then puts the instructions first,
    /// separated by `---`, because Hermes has no `--system-prompt`
    /// flag — the instructions travel as user-turn text, and Hermes'
    /// own profile/workspace rules still apply on top.
    func objectiveText(_ request: ChatRequest) -> String {
        var parts: [String] = []
        let earlier = request.messages.dropLast()
        if !earlier.isEmpty {
            parts.append("<conversation>")
            for m in earlier { parts.append("<\(m.role.rawValue)>\n\(m.content)\n</\(m.role.rawValue)>") }
            parts.append("</conversation>")
        }
        if let last = request.messages.last { parts.append(last.content) }
        return parts.joined(separator: "\n")
    }

    /// Resolves the request's model. Empty/absent means "Hermes'
    /// configured default" (no `--model` flag). A `hermes:` id is
    /// parsed strictly — an invalid one fails before launch, never
    /// with a substituted model. Any other non-empty value is taken
    /// as Hermes' own spec: the provider is already selected in
    /// SwiftCode, so the `hermes:` prefix carries no routing meaning
    /// here (Legacy needed it to keep a bare `provider/model` id
    /// from routing to OpenRouter).
    func resolvedModelID(_ raw: String?) throws -> HermesModelID? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("hermes:") {
            guard let id = HermesModelID.parse(raw) else {
                throw AssistantError.modelNotFound(model: raw, hint: "Expected “hermes:<provider>:<model>” or “hermes:<model>”. Select a Hermes model in Settings; no other model is substituted.")
            }
            return id
        }
        let id = HermesModelID(spec: raw)
        guard !id.model.isEmpty else {
            throw AssistantError.modelNotFound(model: raw, hint: "Expected “hermes:<provider>:<model>” or “hermes:<model>”. Select a Hermes model in Settings; no other model is substituted.")
        }
        return id
    }

    // MARK: - Credentials (SwiftCode deviation from Legacy)

    /// The environment variable Hermes reads for `provider`'s key,
    /// from Hermes' public environment-variable reference. Only
    /// providers whose variable is documented there are mapped;
    /// anything else returns nil and Hermes authenticates itself
    /// from its own `.env` (Legacy behaviour). Never invent a
    /// variable name for an unmapped provider.
    public static func credentialEnvironmentVariable(forProvider provider: String?) -> String? {
        switch provider?.lowercased() {
        case "openrouter": return "OPENROUTER_API_KEY"
        case "openai-api": return "OPENAI_API_KEY"
        default: return nil
        }
    }

    /// The `SecretStore` account holding the key for `provider`.
    /// (Coordinator-owned `SecretAccount` has no Hermes entry yet;
    /// these strings live here until the coordinator adds them.)
    public static func apiKeyAccount(forProvider provider: String?) -> String? {
        guard let provider = provider?.lowercased(), !provider.isEmpty,
              credentialEnvironmentVariable(forProvider: provider) != nil else { return nil }
        return "hermes.\(provider)-api-key"
    }

    /// The child's environment: PATH (with the executable's dir
    /// first), HOME, TMPDIR only — exactly Legacy's controlled
    /// environment, so no `HERMES_*` variable is inherited and a
    /// stray `HERMES_YOLO_MODE` in the parent can never
    /// auto-approve a run — plus the SecretStore key under its
    /// documented variable when one was supplied. The key appears
    /// nowhere else: never in argv, never in an error string (see
    /// `redacted(_:secrets:)`).
    public static func environment(executable: URL, parent: [String: String] = ProcessInfo.processInfo.environment,
                                   apiKey: String? = nil, apiKeyVariable: String? = nil) -> [String: String] {
        var env: [String: String] = [:]
        let binDir = executable.deletingLastPathComponent().path
        let parentPath = parent["PATH"] ?? ""
        env["PATH"] = parentPath.isEmpty ? binDir : "\(binDir):\(parentPath)"
        if let home = parent["HOME"] { env["HOME"] = home }
        if let tmp = parent["TMPDIR"] { env["TMPDIR"] = tmp }
        if let variable = apiKeyVariable, let key = apiKey, !key.isEmpty { env[variable] = key }
        return env
    }

    /// Replaces every known secret value in `text` with
    /// `[redacted]`. Applied to stderr tails before they reach an
    /// error string, so a key can never leak into logs or UI.
    public static func redacted(_ text: String, secrets: [String]) -> String {
        var out = text
        for secret in secrets where !secret.isEmpty {
            out = out.replacingOccurrences(of: secret, with: "[redacted]")
        }
        return out
    }

    /// The exit message, with the usual cause spelled out.
    static func explain(status: Int32, stderrTail: String, secrets: [String]) -> String {
        let tail = redacted(stderrTail, secrets: secrets).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = tail.lowercased()
        if lower.contains("login") || lower.contains("log in") || lower.contains("sign in") || lower.contains("authenticat") {
            return "it needs you to sign in. Run `hermes setup` in Terminal to sign in, then try again. (\(tail.suffix(300)))"
        }
        return tail.isEmpty ? "exit status \(status)" : String(tail.suffix(600))
    }

    // MARK: - Model discovery (Legacy's real source)

    /// Reads the model Hermes is configured to use from its
    /// `config.yaml` (`model.provider` and `model.default`, under
    /// `HERMES_HOME` or `~/.hermes`). Returns `provider:model`
    /// specs, or an empty list when the file has no usable model.
    /// Read-only, model fields only: this never opens `.env` and
    /// never touches a secret. Never launches Hermes (`hermes
    /// model` is an interactive picker that refuses to run without
    /// a terminal). Ported from Legacy's `readConfiguredModelSpecs`.
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

    /// Parses `hermes model` output into model specs. Pure, so tests
    /// can feed sample output without launching Hermes. Strategy:
    /// prefer a `provider:model` token on a line mentioning "model"
    /// (the current-model line), otherwise any provider:model token
    /// in the output. Tokens that look like URLs, session ids, or
    /// key/value labels are ignored; a bare model name on a "model"
    /// line is kept as a bare spec (Hermes resolves it against its
    /// default provider). Ported from Legacy's `parseModelOutput`.
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

    // MARK: - Argument construction

    /// Builds the argv for one run (excluding the executable itself).
    /// Pure over its inputs so tests can assert the exact invocation
    /// without launching anything. Never includes a secret, a prompt,
    /// or a model key: the prompt travels in the query file, never
    /// argv, so it cannot leak into a process listing.
    public static func buildArguments(
        model: HermesModelID?,
        directory: String,
        queryFilePath: String,
        configuration: HermesConfiguration
    ) -> [String] {
        var args: [String] = []
        // --in is a global option: it must precede the subcommand.
        args += ["--in", directory]
        args += ["chat", "--oneshot", "--query-file", queryFilePath, "--format", "stream-json", "--source", "tool"]
        if let provider = model?.provider {
            args += ["--provider", provider]
        }
        if let model = model?.model, !model.isEmpty {
            args += ["--model", model]
        }
        if let toolsets = configuration.normalisedToolsets {
            args += ["--toolsets", toolsets]
        }
        if configuration.maxTurns > 0 {
            args += ["--max-turns", String(configuration.maxTurns)]
        }
        return args
    }
}

// MARK: - Model identity

// `HermesModelID` is declared once, in AssistModelRouting.swift (the
// stored-identifier model shared with the routing layer).

// MARK: - Configuration

/// Hermes launch settings. Only the settings the stream-json
/// interface actually consumes: the executable to launch, the
/// optional toolset restriction, and the optional iteration budget.
/// Model selection lives in the selected model id
/// (`HermesModelID`), never duplicated here. This is a plain value:
/// persistence lives in `AssistantSettings` (coordinator-owned),
/// not in UserDefaults here.
public struct HermesConfiguration: Equatable, Sendable {
    /// Explicit `hermes` executable path. Empty means auto-detect:
    /// PATH plus the usual install locations (see `CLIToolLocator`).
    public var executablePath: String
    /// Optional comma-separated toolsets passed as `--toolsets`
    /// (for example `file,web`). Empty means Hermes' defaults.
    /// Narrowing this is how a user removes terminal / code execution
    /// from a Hermes run.
    public var toolsets: String
    /// Optional `--max-turns` iteration budget. 0 means Hermes'
    /// default (500, or `agent.max_turns` in Hermes config).
    public var maxTurns: Int

    public init(executablePath: String = "", toolsets: String = "", maxTurns: Int = 0) {
        self.executablePath = executablePath
        self.toolsets = toolsets
        self.maxTurns = maxTurns
    }

    /// Normalised toolsets for argv, or nil when Hermes' defaults
    /// should apply. Whitespace-only input is treated as empty so a
    /// stray space can never be passed as a toolset name.
    public var normalisedToolsets: String? {
        let trimmed = toolsets.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Stream-json events

/// The terminal `result` record of a stream-json run, as documented
/// by Hermes. It is authoritative for the final text (text deltas
/// can stop early on a replay gap, while `result.text` is the whole
/// reply) and for the run's exit code.
public struct HermesStreamResult: Equatable, Sendable {
    public let sessionId: String?
    public let exitCode: Int
    public let text: String
    public let error: String?
    /// Token usage from the wire `tokens` object, when Hermes sends it.
    public let tokens: TokenUsage?

    public init(sessionId: String?, exitCode: Int, text: String, error: String?, tokens: TokenUsage? = nil) {
        self.sessionId = sessionId
        self.exitCode = exitCode
        self.text = text
        self.error = error
        self.tokens = tokens
    }
}

/// One parsed stream-json line. `tool_use` / `tool_result` records
/// carry no call id on the wire, so callers that pair them must
/// synthesise stable ids per run.
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
    /// blank lines, malformed JSON, and event types SwiftCode does not
    /// consume — a single bad line must never abort a run.
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
            var tokens: TokenUsage?
            if let t = json["tokens"] as? [String: Any] {
                tokens = TokenUsage(inputTokens: jsonInt(t["input"]), outputTokens: jsonInt(t["output"]))
            }
            return .result(HermesStreamResult(
                sessionId: json["session_id"] as? String,
                exitCode: exitCode,
                text: text,
                error: error,
                tokens: tokens
            ))
        default:
            return .ignored
        }
    }

    static func jsonInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        return (value as? NSNumber)?.intValue
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
    /// Builds the query-file payload: SwiftCode's assembled instructions,
    /// then the task, separated so the task cannot silently merge
    /// into the instructions. This is delivered as the user turn
    /// (Hermes has no `--system-prompt` flag); Hermes' own profile /
    /// workspace rules still apply on top.
    public static func build(systemPrompt: String, objective: String) -> String {
        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return task }
        guard !task.isEmpty else { return prompt }
        return "\(prompt)\n\n---\n\n\(task)"
    }
}

// MARK: - Stream-json → chat events

/// Turns Hermes stream-json lines into `ChatEvent`s, following the
/// host's `CLIEventParser` pattern (Claude Code / Codex /
/// Antigravity). Text deltas stream as `.text`; Hermes tool calls
/// surface as `.activity` (observed only — SwiftCode never executes a
/// tool inside a Hermes run); the terminal `result` record is
/// authoritative: its text is emitted when no delta arrived, its
/// token usage rides on `.finished`, and a non-zero exit code throws
/// `AssistantError.tool` at the result line instead of completing.
public struct HermesStreamEventParser: CLIEventParser {
    public var sawText = false
    public var finished = false
    public var terminalResult: HermesStreamResult?
    public init() {}

    public mutating func parse(_ line: String) throws -> [ChatEvent] {
        switch HermesStreamParser.parseLine(line) {
        case .text(let delta):
            guard !delta.isEmpty else { return [] }
            sawText = true
            return [.text(delta)]
        case .toolUse(let name, let inputJSON):
            return [.activity(Self.describeToolUse(name, inputJSON: inputJSON))]
        case .toolResult(let name, _, let isError, _):
            return [.activity(name + (isError ? " ✗" : " ✓"))]
        case .result(let result):
            terminalResult = result
            guard result.exitCode == 0 else {
                throw AssistantError.tool(name: "Hermes",
                                          message: result.error.map { String($0.prefix(500)) }
                                            ?? "Hermes run failed (exit \(result.exitCode)).")
            }
            var out: [ChatEvent] = []
            if !sawText, !result.text.isEmpty {
                sawText = true
                out.append(.text(result.text))
            }
            return out
        case .system, .ignored:
            return []
        }
    }

    public mutating func finish() -> [ChatEvent] {
        guard let result = terminalResult, !finished else { return [] }
        finished = true
        return [.finished(result.tokens)]
    }

    /// "read_file README.md": the tool name plus the most useful
    /// argument (a path, command, or query) when the input carries one.
    static func describeToolUse(_ name: String, inputJSON: String) -> String {
        guard let data = inputJSON.data(using: .utf8),
              let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return name
        }
        let target = (input["path"] as? String) ?? (input["file_path"] as? String)
            ?? (input["command"] as? String) ?? (input["query"] as? String) ?? (input["pattern"] as? String)
        return target.map { "\(name): \($0)" } ?? name
    }
}


// Ported from Legacy `SwiftCode/Backend/Assist/HermesProvider.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: HermesError, HermesRunRequest, HermesContinuationGuard, HermesTimeoutWorkBox.

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
