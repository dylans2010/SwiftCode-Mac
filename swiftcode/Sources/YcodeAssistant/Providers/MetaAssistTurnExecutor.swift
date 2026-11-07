import Foundation

public enum MetaToolNameSource: Sendable, Equatable {
    case synonym
    case registry
    case alias
    case passthrough
}

public struct MetaNormalizedToolName: Sendable, Equatable {
    public let name: String
    public let source: MetaToolNameSource
    public init(name: String, source: MetaToolNameSource) {
        self.name = name
        self.source = source
    }
}

public enum MetaToolNameNormalizer {
    public static let namespacePrefixes = ["muse.", "Muse.", "muse_", "Muse_", "muse:", "Muse:", "muse-", "Muse-"]

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

public enum MetaTurnNotificationRouter {
    public static func isMuseTool(_ rawName: String, knownToolIDs: Set<String>) -> Bool {
        rawName.hasPrefix("muse.") || rawName.hasPrefix("Muse.") ||
            rawName.hasPrefix("muse_") || rawName.hasPrefix("Muse_") ||
            !knownToolIDs.contains(MetaToolNameNormalizer.normalize(rawName, knownToolIDs: knownToolIDs).name)
    }

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
            return [.ignored]
        default:
            return [.ignored]
        }
    }
}

final class MetaTurnState: @unchecked Sendable {
    let lock = NSLock()
    var tracker: [String: MetaTurnItemState] = [:]
    var unmapped: [String] = []
    var thinking = ""
    var resumed = false

    func appendThinking(_ delta: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        thinking += delta
        guard thinking.contains("\n\n") || thinking.count > 240 else { return nil }
        defer { thinking = "" }
        return String(thinking.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }

    func claimResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

@MainActor
public final class MetaAssistTurnExecutor: Sendable {
    public static let shared = MetaAssistTurnExecutor()

    nonisolated public static let defaultTurnTimeout: TimeInterval = 300

    public private(set) var activeSessionID: String?
    public private(set) var activeWorkspaceRoot: String?
    public private(set) var activeTurnID: String?
    public private(set) var completedTurns: [String: AnyJSON] = [:]
    public private(set) var lastTurnUnmappedToolNames: [String] = []
    public private(set) var reportedModelID: String?

    private let customBridge: MuseCodeMSPBridge?

    private var bridge: MuseCodeMSPBridge {
        customBridge ?? MuseCodeMSPBridge.shared
    }

    public init(bridge: MuseCodeMSPBridge? = nil) {
        self.customBridge = bridge
    }

    public func resetSession() {
        activeSessionID = nil
        activeWorkspaceRoot = nil
        activeTurnID = nil
        completedTurns.removeAll()
        lastTurnUnmappedToolNames = []
        reportedModelID = nil
    }

    public static let clientInfo: AnyJSON = [
        "name": "swiftcode",
        "title": "SwiftCode",
        "version": "1.0.0",
    ]

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

    public static func parseSessionID(_ response: AnyJSON, fallback: String) -> String {
        if let id = response["result"]?["session"]?["sessionId"]?.string, !id.isEmpty { return id }
        if let id = response["session"]?["sessionId"]?.string, !id.isEmpty { return id }
        if let id = response["sessionId"]?.string, !id.isEmpty { return id }
        return fallback
    }

    public static func isSessionNotLoaded(_ error: Error) -> Bool {
        let text = error.localizedDescription
        if text.contains("is not loaded on this host") { return true }
        if let mspError = error as? MuseCodeMSPError {
            if mspError.kind == "sessionNotLoaded" { return true }
            if mspError.message.contains("is not loaded on this host") { return true }
        }
        return false
    }

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
        turnTimeoutSeconds: TimeInterval = MetaAssistTurnExecutor.defaultTurnTimeout,
        onEvent: @escaping @Sendable (ChatEvent) -> Void
    ) async throws {
        guard let executable else { throw MuseCodeCLIError.executableNotFound }
        guard hasCredentials || proxyBaseURL != nil else {
            throw AssistantError.notSignedIn(hint: "Assist with Meta is installed but not signed in. Run `muse` once in Terminal and sign in, then try again.")
        }

        let effectivePrompt = Self.buildEffectivePrompt(instructions: instructions, history: history, prompt: prompt)
        let bridge = self.bridge
        try await bridge.startHost(executable: executable.path, workspaceRoot: workspaceRoot, baseURL: proxyBaseURL)

        let state = MetaTurnState()
        lastTurnUnmappedToolNames = []

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task { @MainActor in
                    bridge.setNotificationHandler { [weak self] (method: String, params: AnyJSON?) in
                        guard let self else { return }
                        Task { @MainActor in
                            await self.handleNotification(
                                method: method, params: params, state: state,
                                continuation: continuation, attachment: attachment,
                                knownToolIDs: knownToolIDs, onEvent: onEvent)
                        }
                    }
                    bridge.setServerRequestHandler({ (_, _, _) -> [String: Any]? in nil })
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
                if turnTimeoutSeconds > 0 {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(turnTimeoutSeconds * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        if state.claimResume() {
                            await bridge.stopHost()
                            continuation.resume(throwing: MuseCodeCLIError.turnTimeout(turnTimeoutSeconds))
                        }
                    }
                }
            }
        } catch {
            bridge.setNotificationHandler(nil as ((String, [String: Any]) -> Void)?)
            lastTurnUnmappedToolNames = state.lock.withLock { state.unmapped }
            if case MuseCodeCLIError.turnTimeout = error {
                resetSession()
            }
            throw error
        }
        lastTurnUnmappedToolNames = state.lock.withLock { state.unmapped }
        bridge.setNotificationHandler(nil as ((String, [String: Any]) -> Void)?)
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
                break
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
        let requirementID: AnyJSON = requirement ?? ["approvalId": .string(approvalID), "sourceIndex": .int(0)]
        _ = try? await bridge.sendCommand(method: "approval/decide", params: [
            "sessionId": .string(sessionID),
            "approvalId": .string(approvalID),
            "requirementId": requirementID,
            "choiceId": .string(choice),
            "feedback": .null,
        ])
    }

    private func runTurn(
        prompt: String,
        effectivePrompt: String,
        modelID: String,
        reasoningEffort: String,
        workspaceRoot: String
    ) async throws {
        if !(await bridge.isInitialized) {
            _ = try await bridge.sendCommand(method: "initialize", params: ["clientInfo": Self.clientInfo])
            try await bridge.sendNotification(method: "initialized", params: [:])
            await bridge.markInitialized()
        }

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

    public func unqueueTurn(turnId: String) async throws {
        guard let sessionId = activeSessionID else { return }
        let cmdId = MuseUUIDv7.generate()
        _ = try await bridge.sendCommand(method: "turn/unqueue", params: [
            "sessionId": .string(sessionId),
            "commandId": .string(cmdId),
            "turnId": .string(turnId),
        ])
    }

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
