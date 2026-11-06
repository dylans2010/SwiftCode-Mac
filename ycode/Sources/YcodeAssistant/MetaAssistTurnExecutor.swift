import Foundation

// MARK: - Meta turn executor (Wave 16, Slice B)
//
// Ported from Legacy (Dylan's own code; direct port authorised
// under MIT):
//   * `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MetaAssistProvider.swift`
//     — `executeTurn`, `normalizeToolName`, `isRateLimitError`,
//     `switchModel`, `unqueueTurn`, `cancelTurn`, and the turn
//     tracker (`TurnTracker.ItemState`).
//
// What this is: the MSP half of a Meta turn. The executor drives
// one `muse serve` host session — initialize once, start or
// resume a session, start a turn with `ifBusy: "queue"`, and
// route the host's notifications into `ChatEvent`s until
// `turn/completed` (or `turn/unqueued` for this turn) arrives.
//
// What is deliberately different from Legacy — read this before
// assuming a behaviour carried over:
//   * NO Autopilot bypass. Legacy decided approvals itself and,
//     in Autopilot mode, approved everything at system level
//     (`isAllowed = isAutopilot ? true : …`). Here every
//     `approval/requested` goes through the host's permission
//     UI (`AgentAttachment.requestPermission`, options
//     `allow_once` / `abort`); with no attachment the decision
//     is `abort`. The `muse` host still executes its own tools
//     itself — Ycode observes them as `.activity` events and
//     never runs a tool inside the provider.
//   * NO Ycode MCP tool execution inside the provider.
//     `YcodeAssistant` does not (and cannot) depend on
//     `YcodeMCP` — the dependency runs the other way — so there
//     is no `MCPServer` to call here. Tool calls the host makes
//     are named (via `MetaToolNameNormalizer`, against Ycode's
//     MCP ids when the host injects them) and reported as
//     activity; they are not executed by Ycode. Wiring Ycode's
//     MCP endpoint into `muse serve` would need a documented
//     CLI mechanism for it, and none was found: Legacy passed no
//     MCP configuration to the host, and Meta's public docs
//     describe `muse serve` only as hosting the session protocol
//     (with SDKs wrapping it). The attachment's `proposeChange`
//     / `readFile` hooks are therefore unused by this provider
//     until such a seam exists; the host's "Ycode's tools are
//     attached" activity line (emitted by the IDE model when any
//     provider attaches) overclaims for Meta and should be
//     qualified by the host.
//   * NO SystemIndex prompt. Legacy prefixed every turn with
//     its canonical system assets (`baselinePrompt`, retrieved
//     instructions, the full native-tool catalog with JSON
//     schemas). Ycode has no `SystemIndexService`, and the MCP
//     tool catalog cannot be listed from this target, so the
//     turn carries the host's own instructions plus the
//     conversation history (last 12 turns) and the current
//     request — nothing invented, nothing from another provider.
//   * NO `LLMService` fallback. Legacy's rate-limit catch ran
//     the turn again through `MuseOtherModelsBridge.executeTurn`
//     (its direct-LLM path). That path needs `LLMService` and
//     `AssistManager` execution, neither of which exists in
//     Ycode; the host-level router (Wave 15 failover) owns
//     cross-provider failover instead. The executor still
//     classifies rate limits (`isRateLimitError`, verbatim
//     rules) so the host can fail over.
//   * NO `MetaAccountAuthService` / login flow. A turn without
//     credentials fails with `.notSignedIn` and a hint to run
//     `muse` once in Terminal; Ycode never launches an
//     interactive `muse login`.
//   * Thinking deltas have no `ChatEvent` case, so they follow
//     the ACP provider's precedent: accumulated and emitted as
//     `.activity("Thinking: …")` once the buffer holds a blank
//     line or passes 240 characters. Text deltas stream as
//     `.text`; tool stdout/stderr deltas are tracked on the item
//     and reported as tool progress activity — never dumped
//     into the chat text (Legacy's own rule).
//   * `session/modelChanged` does not write settings (there is
//     no `AppSettings` here); the executor records the new id
//     in `reportedModelID` for the host to read.
//   * The provider, not the executor, owns the other-models
//     proxy: `executeTurn` takes an optional `proxyBaseURL`
//     (the `MuseOtherModelsBridge` proxy, started by the host
//     when other-model mode is on) and passes it as
//     `--base-url`, exactly as Legacy did.

// MARK: - Tool-name normalization

/// How a normalized tool name was resolved (for the unmapped
/// record: only `.registry` and `.synonym` are confirmed
/// mappings onto Ycode tools).
public enum MetaToolNameSource: Sendable, Equatable {
    /// One of Legacy's hardcoded synonym rules.
    case synonym
    /// Present in the injected Ycode MCP tool ids.
    case registry
    /// A static alias the MCP server itself honours
    /// (`bash` → `use_terminal`, Legacy alias table, Wave 4).
    case alias
    /// No mapping found: the cleaned name, recorded unmapped.
    case passthrough
}

/// The result of normalizing one tool name.
public struct MetaNormalizedToolName: Sendable, Equatable {
    public let name: String
    public let source: MetaToolNameSource
    public init(name: String, source: MetaToolNameSource) {
        self.name = name
        self.source = source
    }
}

/// Normalizes incoming tool identifiers (Legacy
/// `MetaAssistProvider.normalizeToolName`): strips a `Muse.` /
/// `muse.` (etc.) namespace prefix, then maps synonyms to
/// canonical Ycode tool ids — resolved against Ycode's MCP tool
/// registry, NOT Legacy's `AssistManager` registry, which does
/// not exist here.
///
/// The registry is the set of MCP tool ids the host injects
/// (see `MetaAssistProvider.knownToolIDs`): the provider cannot
/// import `YcodeMCP` itself, so until the host injects the live
/// catalogue the set is empty and every non-synonym name is
/// recorded as unmapped rather than silently claimed to exist.
public enum MetaToolNameNormalizer {
    /// Prefixes stripped, in order, first match wins (Legacy).
    public static let namespacePrefixes = ["muse.", "Muse.", "muse_", "Muse_", "muse:", "Muse:", "muse-", "Muse-"]

    /// Aliases the MCP server honours that this executor can
    /// produce on its own (Legacy's alias table; the full table
    /// lives in `MCPServer.toolAliases` and is applied at
    /// `tools/call` time by the server itself).
    public static let mcpAliases: [String: String] = [
        "bash": "use_terminal",
        "sh": "use_terminal",
        "zsh": "use_terminal",
    ]

    public static func normalize(_ name: String?, knownToolIDs: Set<String> = []) -> MetaNormalizedToolName {
        guard let name, !name.isEmpty else { return MetaNormalizedToolName(name: "system_tool", source: .passthrough) }
        var cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in namespacePrefixes where cleaned.hasPrefix(prefix) {
            cleaned = String(cleaned.dropFirst(prefix.count))
            break
        }

        let lower = cleaned.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        if lower == "use_workers" || lower == "useworkers" || lower == "workers" || lower == "workflow" || lower == "use_worker" {
            return MetaNormalizedToolName(name: "use_workers", source: .synonym)
        }
        if lower == "plan_askuser" || lower == "planaskuser" || lower == "askuser" || lower == "ask_user" {
            return MetaNormalizedToolName(name: "plan-AskUser", source: .synonym)
        }
        if lower == "report_to_user" || lower == "reporttouser" || lower == "report" {
            return MetaNormalizedToolName(name: "report_to_user", source: .synonym)
        }

        if knownToolIDs.contains(cleaned) {
            return MetaNormalizedToolName(name: cleaned, source: .registry)
        }
        if let canonical = knownToolIDs.first(where: { $0.lowercased() == lower }) {
            return MetaNormalizedToolName(name: canonical, source: .registry)
        }
        if let aliased = mcpAliases[cleaned] ?? mcpAliases[lower] {
            return MetaNormalizedToolName(name: aliased, source: .alias)
        }
        return MetaNormalizedToolName(name: cleaned, source: .passthrough)
    }
}

// MARK: - Turn tracker

/// Per-turn item state (Legacy `TurnTracker.ItemState`).
public struct MetaTurnItemState: Sendable, Equatable {
    public let kind: String
    public let tool: String?
    public let args: String
    public var output: String = ""
    public let startedAt: Date = Date()
    public init(kind: String, tool: String?, args: String) {
        self.kind = kind
        self.tool = tool
        self.args = args
    }
}

/// What the notification router produces for one host
/// notification. The executor maps these onto `ChatEvent`s,
/// approval decisions, and the turn's terminal continuation.
public enum MetaTurnEvent: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case activity(String)
    case toolStarted(callID: String, toolName: String, argumentsJSON: String, isMuseTool: Bool)
    case toolProgress(callID: String, message: String)
    case toolCompleted(callID: String, toolName: String, output: String?, argumentsJSON: String, isMuseTool: Bool)
    case turnCompleted(turnID: String?)
    case turnUnqueued(turnID: String?)
    case modelChanged(String)
    case approvalRequested(sessionID: String, approvalID: String, action: String, requirement: AnyJSON?)
    case ignored
}

/// Routes one MSP notification into turn events, against a
/// tracker (Legacy's `bridge.setNotificationHandler` closure,
/// factored pure so tests can drive it with fixtures).
/// The tracker is mutated in place; unmapped tool names are
/// appended to `unmappedToolNames` (deduped, in order).
public enum MetaTurnNotificationRouter {
    /// Whether a raw tool name is a Muse SDK tool (Legacy's
    /// `isMuseTool` test): a `muse.`/`Muse.`-prefixed name, or a
    /// name no Ycode registry knows.
    public static func isMuseTool(_ rawName: String, knownToolIDs: Set<String>) -> Bool {
        rawName.hasPrefix("muse.") || rawName.hasPrefix("Muse.") ||
            rawName.hasPrefix("muse_") || rawName.hasPrefix("Muse_") ||
            !knownToolIDs.contains(MetaToolNameNormalizer.normalize(rawName, knownToolIDs: knownToolIDs).name)
    }

    /// The human-readable line for a tool start, in the Hermes
    /// provider's style: name plus the most useful argument.
    public static func describeToolUse(_ name: String, argumentsJSON: String) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return name
        }
        let target = (input["path"] as? String) ?? (input["file_path"] as? String)
            ?? (input["command"] as? String) ?? (input["query"] as? String) ?? (input["pattern"] as? String)
        return target.map { "\(name): \($0)" } ?? name
    }

    public static func route(
        method: String,
        params: AnyJSON?,
        tracker: inout [String: MetaTurnItemState],
        unmappedToolNames: inout [String],
        knownToolIDs: Set<String>,
        activeTurnID: String?
    ) -> [MetaTurnEvent] {
        switch method {
        case "item/started":
            guard let item = params?["item"]?.object,
                  let itemId = item["itemId"]?.string else { return [.ignored] }
            let kind = item["kind"]?.string ?? ""
            let tool = item["tool"]?.string
            let rawArgs = item["args"]?.string ?? ""
            tracker[itemId] = MetaTurnItemState(kind: kind, tool: tool, args: rawArgs)
            guard kind == "toolCall" || kind == "userShell" else { return [.ignored] }
            let rawToolName = tool ?? (kind == "userShell" ? "bash" : "system_tool")
            let normalized = MetaToolNameNormalizer.normalize(rawToolName, knownToolIDs: knownToolIDs)
            if normalized.source == .passthrough, !unmappedToolNames.contains(normalized.name) {
                unmappedToolNames.append(normalized.name)
            }
            return [.toolStarted(callID: itemId, toolName: normalized.name, argumentsJSON: rawArgs,
                                 isMuseTool: isMuseTool(rawToolName, knownToolIDs: knownToolIDs)),
                    .activity(describeToolUse(normalized.name, argumentsJSON: rawArgs))]
        case "item/delta":
            let itemId = params?["itemId"]?.string
            let field = params?["field"]?.string
            let delta = (params?["delta"]?.string)
                ?? (params?["delta"]?["text"]?.string)
                ?? ""
            guard !delta.isEmpty else { return [.ignored] }
            let kind = itemId.flatMap { tracker[$0]?.kind } ?? ""
            if field == "output" || kind == "toolCall" || kind == "userShell" {
                // Tool stdout/stderr — tracked, never chat text.
                if let id = itemId {
                    tracker[id]?.output.append(delta)
                }
                let clean = delta.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty, let id = itemId else { return [.ignored] }
                return [.toolProgress(callID: id, message: clean)]
            } else if field?.hasPrefix("summary") == true || kind == "reasoning" {
                return [.thinking(delta)]
            } else if field == "text" || field == nil || kind == "agentMessage" {
                return [.text(delta)]
            }
            return [.ignored]
        case "item/completed":
            guard let item = params?["item"]?.object,
                  let itemId = item["itemId"]?.string else { return [.ignored] }
            let kind = item["kind"]?.string ?? tracker[itemId]?.kind ?? ""
            let tool = item["tool"]?.string ?? tracker[itemId]?.tool
            let rawArgs = item["args"]?.string ?? tracker[itemId]?.args ?? ""
            let recordedOutput = tracker[itemId]?.output ?? ""
            let visibleOutput = (item["visibleOutput"]?.string) ?? recordedOutput
            defer { tracker.removeValue(forKey: itemId) }
            if kind == "toolCall" || kind == "userShell" {
                let rawToolName = tool ?? (kind == "userShell" ? "bash" : "system_tool")
                let normalized = MetaToolNameNormalizer.normalize(rawToolName, knownToolIDs: knownToolIDs)
                if normalized.source == .passthrough, !unmappedToolNames.contains(normalized.name) {
                    unmappedToolNames.append(normalized.name)
                }
                return [.toolCompleted(callID: itemId, toolName: normalized.name,
                                      output: visibleOutput.isEmpty ? nil : visibleOutput,
                                      argumentsJSON: rawArgs,
                                      isMuseTool: isMuseTool(rawToolName, knownToolIDs: knownToolIDs))]
            }
            return [.ignored]
        case "turn/completed":
            return [.turnCompleted(turnID: params?["turnId"]?.string)]
        case "turn/unqueued":
            let unqueuedTurnId = params?["turnId"]?.string
            guard unqueuedTurnId == activeTurnID else { return [.ignored] }
            return [.turnUnqueued(turnID: unqueuedTurnId)]
        case "session/modelChanged":
            guard let newModelId = params?["modelId"]?.string else { return [.ignored] }
            return [.modelChanged(newModelId)]
        case "approval/requested":
            guard let sessionId = params?["sessionId"]?.string,
                  let approvalId = params?["approvalId"]?.string else { return [.ignored] }
            let action = params?["action"]?.string ?? params?["subject"]?.string ?? "operation"
            let requirement = params?["currentRequirementId"] ?? params?["requirementId"]
            return [.approvalRequested(sessionID: sessionId, approvalID: approvalId, action: action, requirement: requirement)]
        case "approval/resolved":
            return [.ignored] // Durable policy result; observed only.
        default:
            return [.ignored]
        }
    }
}

// MARK: - Turn state (one turn's mutable box)

/// The mutable state of one running turn, shared between the
/// bridge's reader task (which delivers notifications) and the
/// executor actor (which resumes the turn). Guarded by one lock.
final class MetaTurnState: @unchecked Sendable {
    let lock = NSLock()
    var tracker: [String: MetaTurnItemState] = [:]
    var unmapped: [String] = []
    var thinking = ""
    var resumed = false

    /// Appends a thinking delta; returns the accumulated text to
    /// emit when the buffer holds a blank line or passes 240
    /// characters (the ACP provider's precedent), else nil.
    func appendThinking(_ delta: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        thinking += delta
        guard thinking.contains("\n\n") || thinking.count > 240 else { return nil }
        defer { thinking = "" }
        return String(thinking.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }

    /// Marks the turn resumed; true when this call won the race.
    func claimResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

// MARK: - Executor

/// Executes Meta turns against one MSP host (Legacy
/// `MetaAssistProvider.executeTurn` + session bookkeeping).
/// Actor-isolated so a second turn waits for the first: the
/// shared bridge carries one notification handler at a time.
public actor MetaAssistTurnExecutor {
    public static let shared = MetaAssistTurnExecutor()

    public private(set) var activeSessionID: String?
    public private(set) var activeWorkspaceRoot: String?
    public private(set) var activeTurnID: String?
    public private(set) var completedTurns: [String: AnyJSON] = [:]
    /// Tool names from the last turn that no mapping confirmed
    /// (see `MetaToolNameNormalizer`).
    public private(set) var lastTurnUnmappedToolNames: [String] = []
    /// The model id the host last reported via
    /// `session/modelChanged`, if any.
    public private(set) var reportedModelID: String?

    private let bridge: MuseCodeMSPBridge

    public init(bridge: MuseCodeMSPBridge = .shared) {
        self.bridge = bridge
    }

    public func resetSession() {
        activeSessionID = nil
        activeWorkspaceRoot = nil
        activeTurnID = nil
        completedTurns.removeAll()
        lastTurnUnmappedToolNames = []
        reportedModelID = nil
    }

    /// The client identity sent with `initialize` (Legacy).
    public static let clientInfo: AnyJSON = [
        "name": "swiftcode",
        "title": "SwiftCode",
        "version": "1.0.0",
    ]

    /// Builds the turn's input text: the host's instructions,
    /// then the recent history (last 12 turns, excluding a
    /// duplicate of the current prompt), then the current
    /// request. Legacy also prepended SystemIndex assets and
    /// the full native-tool catalog; Ycode has neither (see the
    /// file header), so nothing is invented in their place.
    public static func buildEffectivePrompt(instructions: String, history: [ChatMessage], prompt: String) -> String {
        var parts: [String] = []
        let system = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty { parts.append(system) }
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredHistory = history.filter {
            let t = $0.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && t != cleanPrompt
        }
        if !filteredHistory.isEmpty {
            let historyText = filteredHistory.suffix(12).map { msg in
                let roleName = (msg.role == .user) ? "User" : "Assist"
                return "[\(roleName)]:\n\(msg.content)"
            }.joined(separator: "\n\n")
            parts.append("""
            # PREVIOUS CONVERSATION HISTORY:
            The following is the recent conversation history in this project session. Maintain full continuity with past messages, decisions, and discussions so the user never has to repeat context.

            \(historyText)
            """)
        }
        parts.append("# CURRENT USER REQUEST\n\(prompt)")
        return parts.joined(separator: "\n\n")
    }

    /// Parses a `model/list` response into catalog items
    /// (Legacy `fetchModels`). Returns nil when the response
    /// carries no usable list — the caller falls back to
    /// `MetaAssistProvider.fallbackModels`.
    public static func parseModelList(_ response: AnyJSON) -> [MetaModelItem]? {
        guard let modelsArray = response["result"]?["models"]?.array else { return nil }
        var items: [MetaModelItem] = []
        for dict in modelsArray {
            guard let modelId = dict["modelId"]?.string, !modelId.isEmpty else { continue }
            items.append(MetaModelItem(
                modelId: modelId,
                displayLabel: dict["displayLabel"]?.string ?? modelId,
                releaseDate: dict["releaseDate"]?.string,
                description: dict["description"]?.string,
                contextLimit: dict["contextLimit"]?.int ?? 1_000_000,
                outputLimit: dict["outputLimit"]?.int ?? 128_000,
                isDefault: dict["isDefault"]?.bool ?? false,
                variants: dict["variants"]?.array?.compactMap(\.string) ?? [],
                defaultReasoningEffort: dict["defaultReasoningEffort"]?.string
            ))
        }
        return items.isEmpty ? nil : items
    }

    /// Extracts a session id from a `session/start` response
    /// (Legacy tried `result.session.sessionId`, then
    /// `session.sessionId`, then a top-level `sessionId`, then
    /// fell back to the command id).
    public static func parseSessionID(_ response: AnyJSON, fallback: String) -> String {
        if let id = response["result"]?["session"]?["sessionId"]?.string, !id.isEmpty { return id }
        if let id = response["session"]?["sessionId"]?.string, !id.isEmpty { return id }
        if let id = response["sessionId"]?.string, !id.isEmpty { return id }
        return fallback
    }

    /// Whether the error is a "session is not loaded on this
    /// host" failure (Legacy's retry trigger for `turn/start`):
    /// the text, or an `MspError` with kind `sessionNotLoaded`.
    public static func isSessionNotLoaded(_ error: Error) -> Bool {
        let text = error.localizedDescription
        if text.contains("is not loaded on this host") { return true }
        if let mspError = error as? MuseCodeMSPError {
            if mspError.kind == "sessionNotLoaded" { return true }
            if mspError.message.contains("is not loaded on this host") { return true }
        }
        return false
    }

    /// Detects a rate-limit / quota / capacity failure (Legacy
    /// `isRateLimitError`, verbatim rules, including the
    /// `MuseCodeMSPError.reason` check).
    public static func isRateLimitError(_ error: Error) -> Bool {
        if let mspError = error as? MuseCodeMSPError {
            let reason = mspError.reason?.lowercased() ?? ""
            let msg = mspError.message.lowercased()
            if reason.contains("rate_limit") || reason.contains("quota") || reason.contains("limit") || reason.contains("429") ||
                msg.contains("rate limit") || msg.contains("quota") || msg.contains("429") || msg.contains("limit reached") {
                return true
            }
        }
        let desc = error.localizedDescription.lowercased()
        return desc.contains("429") ||
            desc.contains("rate limit") ||
            desc.contains("rate_limit") ||
            desc.contains("quota") ||
            desc.contains("resource_exhausted") ||
            desc.contains("too many requests") ||
            desc.contains("limit reached") ||
            desc.contains("hit your limit") ||
            desc.contains("overloaded") ||
            desc.contains("capacity")
    }

    /// Initializes the host session and executes one turn,
    /// streaming events back through `onEvent`. The caller yields
    /// `.finished` after this returns.
    ///
    /// - Parameters:
    ///   - executable: the located `muse` binary; nil throws
    ///     `MuseCodeCLIError.executableNotFound`.
    ///   - hasCredentials: whether a credential file exists;
    ///     false (and no proxy) throws `.notSignedIn` — Ycode
    ///     never launches an interactive login.
    ///   - proxyBaseURL: the other-models proxy URL, when the
    ///     host started one; passed as `--base-url`.
    ///   - attachment: the agent-mode attachment; its
    ///     `requestPermission` decides approvals. Nil means
    ///     every approval is denied (`abort`).
    ///   - knownToolIDs: Ycode MCP tool ids for name resolution.
    public func executeTurn(
        prompt: String,
        history: [ChatMessage] = [],
        instructions: String = "",
        modelID: String,
        reasoningEffort: String = "high",
        workspaceRoot: String,
        executable: URL?,
        hasCredentials: Bool,
        proxyBaseURL: String? = nil,
        attachment: AgentAttachment? = nil,
        knownToolIDs: Set<String> = [],
        onEvent: @escaping @Sendable (ChatEvent) -> Void
    ) async throws {
        guard let executable else { throw MuseCodeCLIError.executableNotFound }
        guard hasCredentials || proxyBaseURL != nil else {
            throw AssistantError.notSignedIn(hint: "Assist with Meta is installed but not signed in. Run `muse` once in Terminal and sign in, then try again.")
        }

        let effectivePrompt = Self.buildEffectivePrompt(instructions: instructions, history: history, prompt: prompt)
        let bridge = self.bridge
        try await bridge.startHost(executable: executable, workspaceRoot: workspaceRoot, baseURL: proxyBaseURL)

        let state = MetaTurnState()
        lastTurnUnmappedToolNames = []

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task {
                    await bridge.setNotificationHandler { [weak self] method, params in
                        guard let self else { return }
                        Task {
                            await self.handleNotification(
                                method: method, params: params, state: state,
                                continuation: continuation, attachment: attachment,
                                knownToolIDs: knownToolIDs, onEvent: onEvent)
                        }
                    }
                    await bridge.setServerRequestHandler { _, _, _ in nil }
                    do {
                        try await self.runTurn(
                            prompt: prompt, effectivePrompt: effectivePrompt, modelID: modelID,
                            reasoningEffort: reasoningEffort, workspaceRoot: workspaceRoot)
                    } catch {
                        if state.claimResume() {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } catch {
            await bridge.setNotificationHandler(nil)
            lastTurnUnmappedToolNames = state.lock.withLock { state.unmapped }
            throw error
        }
        lastTurnUnmappedToolNames = state.lock.withLock { state.unmapped }
        await bridge.setNotificationHandler(nil)
    }

    private func handleNotification(
        method: String,
        params: AnyJSON?,
        state: MetaTurnState,
        continuation: CheckedContinuation<Void, Error>,
        attachment: AgentAttachment?,
        knownToolIDs: Set<String>,
        onEvent: @escaping @Sendable (ChatEvent) -> Void
    ) async {
        let events: [MetaTurnEvent] = state.lock.withLock {
            var tracker = state.tracker
            var unmapped = state.unmapped
            let routed = MetaTurnNotificationRouter.route(
                method: method, params: params, tracker: &tracker,
                unmappedToolNames: &unmapped, knownToolIDs: knownToolIDs,
                activeTurnID: activeTurnID)
            state.tracker = tracker
            state.unmapped = unmapped
            return routed
        }
        for event in events {
            switch event {
            case .text(let delta):
                onEvent(.text(delta))
            case .thinking(let delta):
                if let flushed = state.appendThinking(delta) {
                    onEvent(.activity("Thinking: \(flushed)"))
                }
            case .activity(let line):
                onEvent(.activity(line))
            case .toolStarted:
                break // The router's `.activity` line already covers it.
            case .toolProgress(_, let message):
                onEvent(.activity(message))
            case .toolCompleted(_, let toolName, _, _, _):
                onEvent(.activity("\(toolName) ✓"))
            case .turnCompleted(let turnID):
                if let turnID { completedTurns[turnID] = params ?? .null }
                if state.claimResume() {
                    continuation.resume(returning: ())
                }
            case .turnUnqueued:
                if state.claimResume() {
                    continuation.resume(returning: ())
                }
            case .modelChanged(let newModelId):
                reportedModelID = newModelId
            case .approvalRequested(let sessionID, let approvalID, let action, let requirement):
                await decideApproval(sessionID: sessionID, approvalID: approvalID, action: action,
                                     requirement: requirement, attachment: attachment)
            case .ignored:
                break
            }
        }
    }

    /// Answers one `approval/requested` (Legacy's approval
    /// branch, minus Autopilot): asks the host's permission UI
    /// when attached, otherwise denies. Only the id `allow_once`
    /// ever reaches the host as an allow; anything else,
    /// including a cancelled prompt, becomes `abort`.
    private func decideApproval(
        sessionID: String,
        approvalID: String,
        action: String,
        requirement: AnyJSON?,
        attachment: AgentAttachment?
    ) async {
        var choice = "abort"
        if let attachment {
            let options = [
                AgentAttachment.PermissionOption(id: "allow_once", name: "Allow once", kind: "allow_once"),
                AgentAttachment.PermissionOption(id: "abort", name: "Abort", kind: "reject_once"),
            ]
            let chosen = await attachment.requestPermission("Assist with Meta wants to \(action)", options)
            if chosen == "allow_once" { choice = "allow_once" }
        }
        // Legacy's fallback requirement when the host sent neither
        // `currentRequirementId` nor `requirementId`.
        let requirementID: AnyJSON = requirement ?? ["approvalId": .string(approvalID), "sourceIndex": .int(0)]
        _ = try? await bridge.sendCommand(method: "approval/decide", params: [
            "sessionId": .string(sessionID),
            "approvalId": .string(approvalID),
            "requirementId": requirementID,
            "choiceId": .string(choice),
            "feedback": .null,
        ])
    }

    // MARK: - Session / turn plumbing

    /// Runs the initialize → session → turn sequence (Legacy's
    /// `Task { @MainActor in … }` block inside `executeTurn`).
    /// Returns once `turn/start` is accepted; the turn itself
    /// completes through the `turn/completed` notification.
    private func runTurn(
        prompt: String,
        effectivePrompt: String,
        modelID: String,
        reasoningEffort: String,
        workspaceRoot: String
    ) async throws {
        // 1. Initialize & handshake ONLY ONCE across the lifetime
        // of the bridge.
        if !(await bridge.isInitialized) {
            _ = try await bridge.sendCommand(method: "initialize", params: ["clientInfo": Self.clientInfo])
            try await bridge.sendNotification(method: "initialized", params: [:])
            await bridge.markInitialized()
        }

        // 2. Start or resume the session.
        var sessionId = ""
        if let existing = activeSessionID, activeWorkspaceRoot == workspaceRoot {
            do {
                _ = try await bridge.sendCommand(method: "session/resume", params: [
                    "sessionId": .string(existing),
                    "history": "inline",
                ])
                sessionId = existing
            } catch {
                activeSessionID = nil
            }
        }
        if sessionId.isEmpty {
            let commandId = MuseUUIDv7.generate()
            let res = try await bridge.sendCommand(method: "session/start", params: [
                "commandId": .string(commandId),
                "workspaceRoot": .string(workspaceRoot),
                "modelId": .string(modelID),
            ])
            sessionId = Self.parseSessionID(res, fallback: commandId)
            activeSessionID = sessionId
            activeWorkspaceRoot = workspaceRoot
        }

        // 3. Start the turn with a UUIDv7 commandId, reasoning
        // effort, and `ifBusy: "queue"`.
        let turnCmdId = MuseUUIDv7.generate()
        activeTurnID = turnCmdId
        func turnParams(sessionID: String) -> AnyJSON {
            [
                "commandId": .string(turnCmdId),
                "sessionId": .string(sessionID),
                "reasoningEffort": .string(reasoningEffort),
                "ifBusy": "queue",
                "displayText": .string(prompt),
                "input": .array([["type": "text", "text": .string(effectivePrompt)]]),
            ]
        }
        let turnRes: AnyJSON
        do {
            turnRes = try await bridge.sendCommand(method: "turn/start", params: turnParams(sessionID: sessionId))
        } catch {
            if Self.isSessionNotLoaded(error) {
                // The session is not loaded on this host: start a
                // fresh session and retry the turn once (Legacy).
                let freshCmdId = MuseUUIDv7.generate()
                let freshRes = try await bridge.sendCommand(method: "session/start", params: [
                    "commandId": .string(freshCmdId),
                    "workspaceRoot": .string(workspaceRoot),
                    "modelId": .string(modelID),
                ])
                let freshSessionId = Self.parseSessionID(freshRes, fallback: freshCmdId)
                activeSessionID = freshSessionId
                activeWorkspaceRoot = workspaceRoot
                sessionId = freshSessionId
                turnRes = try await bridge.sendCommand(method: "turn/start", params: turnParams(sessionID: sessionId))
            } else {
                throw error
            }
        }
        if let returnedTurnId = turnRes["result"]?["turnId"]?.string {
            activeTurnID = returnedTurnId
        }
    }

    // MARK: - Model / turn control

    /// Switches the active model mid-session via
    /// `session/setModel` without losing session state (Legacy
    /// `switchModel`). With no session, the host just records
    /// the choice (the provider's next turn uses it).
    public func switchModel(modelID: String, providerID: String = "openai") async throws {
        guard let sessionId = activeSessionID else { return }
        guard await bridge.isRunning else { return }
        let cmdId = MuseUUIDv7.generate()
        _ = try await bridge.sendCommand(method: "session/setModel", params: [
            "sessionId": .string(sessionId),
            "commandId": .string(cmdId),
            "model": ["providerId": .string(providerID), "modelId": .string(modelID)],
        ])
    }

    /// Un-queues / reclaims a pending turn before it executes
    /// (Legacy `unqueueTurn`).
    public func unqueueTurn(turnId: String) async throws {
        guard let sessionId = activeSessionID else { return }
        let cmdId = MuseUUIDv7.generate()
        _ = try await bridge.sendCommand(method: "turn/unqueue", params: [
            "sessionId": .string(sessionId),
            "commandId": .string(cmdId),
            "turnId": .string(turnId),
        ])
    }

    /// Cancels the current turn (Legacy `cancelTurn`). The
    /// `already_terminal` race is swallowed: a turn that reached
    /// its own terminal naturally is not a failure. (Legacy also
    /// cancelled the other-models bridge's active task; Ycode's
    /// other-models path has no such task — the proxy streams
    /// through the MSP host, which this cancel reaches.)
    public func cancelTurn() async {
        guard let sessionId = activeSessionID else { return }
        let turnId = activeTurnID ?? ""
        let cmdId = MuseUUIDv7.generate()
        var params: [String: AnyJSON] = [
            "sessionId": .string(sessionId),
            "commandId": .string(cmdId),
        ]
        if !turnId.isEmpty {
            params["turnId"] = .string(turnId)
        }
        do {
            _ = try await bridge.sendCommand(method: "turn/cancel", params: .object(params))
        } catch {
            if let mspError = error as? MuseCodeMSPError, mspError.reason == "already_terminal" {
                return
            }
        }
    }
}
