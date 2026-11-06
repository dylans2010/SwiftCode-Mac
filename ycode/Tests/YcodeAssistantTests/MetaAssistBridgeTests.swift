import Foundation
import Testing
@testable import YcodeAssistant

// Wave 16, Slice B: Muse Code MSP bridge + lifecycle + slash
// commands + other-models bridge + turn executor. Fixtures only:
// no live `muse` binary, no real credentials. The one live
// process test drives a fixture Python script masquerading as
// `muse` (skipped when python3 is absent).

@Suite(.serialized) struct MetaAssistBridgeTests {
    // MARK: - Helpers

    static func absentLocator() -> CLIToolLocator {
        CLIToolLocator(environment: ["PATH": ""], home: "/nonexistent-meta-test-home",
                       isExecutable: { _ in false })
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-bridge-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func homeWithCredentials() throws -> URL {
        let dir = try tempDir()
        let configDir = dir.appendingPathComponent(".config/muse")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        // An empty auth file: existence only, never read.
        try "{}".write(to: configDir.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        return dir
    }

    /// A fixture `muse` script: a Python NDJSON host that
    /// answers initialize / model/list / session/start /
    /// session/resume / turn/start / turn/cancel /
    /// approval/decide, logs every received method to
    /// `FAKE_MUSE_LOG`, and emits a canned turn (two text
    /// deltas, then turn/completed). Set `FAKE_MUSE_APPROVAL=1`
    /// to emit an `approval/requested` notification before the
    /// turn completes.
    static let fakeMuseScript = """
        #!/usr/bin/env python3
        import sys, json, os
        log_path = os.environ.get("FAKE_MUSE_LOG", "")
        want_approval = os.environ.get("FAKE_MUSE_APPROVAL", "") == "1"
        def log(method):
            if log_path:
                with open(log_path, "a") as f:
                    f.write(method + "\\n")
        def send(obj):
            sys.stdout.write(json.dumps(obj) + "\\n")
            sys.stdout.flush()
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except Exception:
                continue
            method = msg.get("method", "")
            rid = msg.get("id")
            log(method)
            if method == "initialize":
                send({"jsonrpc": "2.0", "id": rid, "result": {"capabilities": {}}})
            elif method == "model/list":
                send({"jsonrpc": "2.0", "id": rid, "result": {"models": [
                    {"modelId": "muse-wonder-1.0", "displayLabel": "muse-wonder-1.0",
                     "releaseDate": "2026-10-12", "contextLimit": 1007997,
                     "outputLimit": 128000, "isDefault": True,
                     "variants": ["high"], "defaultReasoningEffort": "high"}]}})
            elif method == "session/start":
                send({"jsonrpc": "2.0", "id": rid, "result": {"session": {"sessionId": "sess-1"}}})
            elif method == "session/resume":
                send({"jsonrpc": "2.0", "id": rid, "result": {}})
            elif method == "turn/start":
                send({"jsonrpc": "2.0", "id": rid, "result": {"turnId": "turn-1"}})
                send({"jsonrpc": "2.0", "method": "item/started", "params": {"item": {"itemId": "i-1", "kind": "agentMessage"}}})
                send({"jsonrpc": "2.0", "method": "item/delta", "params": {"itemId": "i-1", "field": "text", "delta": "Hello "}})
                send({"jsonrpc": "2.0", "method": "item/delta", "params": {"itemId": "i-1", "field": "text", "delta": "world"}})
                if want_approval:
                    send({"jsonrpc": "2.0", "method": "approval/requested", "params": {"sessionId": "sess-1", "approvalId": "ap-1", "action": "run tests"}})
                send({"jsonrpc": "2.0", "method": "item/completed", "params": {"item": {"itemId": "i-1", "kind": "agentMessage", "text": "Hello world"}}})
                send({"jsonrpc": "2.0", "method": "turn/completed", "params": {"turnId": "turn-1"}})
            elif method == "turn/cancel":
                send({"jsonrpc": "2.0", "id": rid, "result": {}})
            elif method == "approval/decide":
                send({"jsonrpc": "2.0", "id": rid, "result": {}})
            elif method == "session/setModel":
                send({"jsonrpc": "2.0", "id": rid, "result": {}})
            elif method == "turn/unqueue":
                send({"jsonrpc": "2.0", "id": rid, "result": {}})
            else:
                send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "Method not found: " + method}})
        """

    /// Installs the fixture `muse` into a temp dir and returns
    /// the dir, the log path, and a locator that finds it. The
    /// caller must remove the dir afterwards.
    static func installFakeMuse(approval: Bool = false) throws -> (dir: URL, log: URL, locator: CLIToolLocator) {
        let dir = try tempDir()
        let script = dir.appendingPathComponent("muse")
        try fakeMuseScript.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let log = dir.appendingPathComponent("methods.log")
        var environment: [String: String] = ["PATH": dir.path]
        // The fake reads its flags from the environment at spawn;
        // the bridge inherits the parent environment, so set them
        // on this process for the test's duration. The suite is
        // serialized, so no other test can observe them mid-flight.
        if approval { _ = setenv("FAKE_MUSE_APPROVAL", "1", 1) }
        _ = setenv("FAKE_MUSE_LOG", log.path, 1)
        let locator = CLIToolLocator(environment: environment, home: dir.path)
        return (dir, log, locator)
    }

    static func clearFakeMuseEnv() {
        unsetenv("FAKE_MUSE_APPROVAL")
        unsetenv("FAKE_MUSE_LOG")
    }

    /// Records permission prompts (the requestPermission closure
    /// is @Sendable, so it cannot mutate a captured var).
    final class PermissionAskedBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(String, [AgentAttachment.PermissionOption])] = []
        func add(_ title: String, _ options: [AgentAttachment.PermissionOption]) {
            lock.lock(); items.append((title, options)); lock.unlock()
        }
        var all: [(String, [AgentAttachment.PermissionOption])] {
            lock.lock(); defer { lock.unlock() }; return items
        }
    }

    static func pythonAvailable() -> Bool {
        FileManager.default.fileExists(atPath: "/usr/bin/python3")
    }

    // MARK: - UUIDv7

    @Test func uuidv7ShapeAndVersion() {
        let id = MuseUUIDv7.generate()
        let parts = id.split(separator: "-")
        #expect(parts.count == 5)
        #expect(parts[0].count == 8 && parts[1].count == 4 && parts[2].count == 4 && parts[3].count == 4 && parts[4].count == 12)
        #expect(parts[2].first == "7") // version 7
        #expect(["8", "9", "a", "b"].contains(String(parts[3].first!))) // RFC 9562 variant
        #expect(MuseUUIDv7.generate() != id)
        let ms = MuseUUIDv7.timestampMilliseconds(of: id)
        #expect(ms != nil)
        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        #expect(ms! <= now && now - ms! < 60_000)
    }

    // MARK: - Bridge argv / environment

    @Test func bridgeArguments() {
        #expect(MuseCodeMSPBridge.hostArguments(baseURL: nil) == ["serve"])
        #expect(MuseCodeMSPBridge.hostArguments(baseURL: "") == ["serve"])
        #expect(MuseCodeMSPBridge.hostArguments(baseURL: "http://127.0.0.1:19855") ==
            ["--base-url", "http://127.0.0.1:19855", "serve"])
    }

    @Test func bridgeEnvironmentAppendsHomebrewPaths() {
        let env = MuseCodeMSPBridge.hostEnvironment(parent: ["PATH": "/usr/bin"])
        #expect(env["PATH"] == "/usr/bin:/opt/homebrew/bin:/usr/local/bin")
    }

    @Test func bridgeStartWithoutExecutableThrows() async {
        let bridge = MuseCodeMSPBridge()
        do {
            try await bridge.startHost(executable: URL(fileURLWithPath: "/nonexistent/muse"), workspaceRoot: "/tmp")
            Issue.record("expected startHost to throw")
        } catch {
            // Any launch failure is fine; the host never started.
            #expect(await bridge.isRunning == false)
        }
    }

    // MARK: - Tool-name normalization

    @Test func normalizeToolName() {
        let known: Set<String> = ["file_read", "file_write", "plan-AskUser", "use_terminal"]
        #expect(MetaToolNameNormalizer.normalize(nil).name == "system_tool")
        #expect(MetaToolNameNormalizer.normalize("").name == "system_tool")
        #expect(MetaToolNameNormalizer.normalize("Muse.file_read", knownToolIDs: known) ==
            MetaNormalizedToolName(name: "file_read", source: .registry))
        #expect(MetaToolNameNormalizer.normalize("muse_file_write", knownToolIDs: known) ==
            MetaNormalizedToolName(name: "file_write", source: .registry))
        #expect(MetaToolNameNormalizer.normalize("FILE_READ", knownToolIDs: known) ==
            MetaNormalizedToolName(name: "file_read", source: .registry))
        #expect(MetaToolNameNormalizer.normalize("use workers") ==
            MetaNormalizedToolName(name: "use_workers", source: .synonym))
        #expect(MetaToolNameNormalizer.normalize("Muse.plan-askuser") ==
            MetaNormalizedToolName(name: "plan-AskUser", source: .synonym))
        #expect(MetaToolNameNormalizer.normalize("report") ==
            MetaNormalizedToolName(name: "report_to_user", source: .synonym))
        #expect(MetaToolNameNormalizer.normalize("bash") ==
            MetaNormalizedToolName(name: "use_terminal", source: .alias))
        let unmapped = MetaToolNameNormalizer.normalize("some_future_tool")
        #expect(unmapped == MetaNormalizedToolName(name: "some_future_tool", source: .passthrough))
        // Without an injected registry, a real MCP name is
        // recorded as unmapped, never claimed to exist.
        #expect(MetaToolNameNormalizer.normalize("file_read").source == .passthrough)
    }

    // MARK: - Notification routing (fixtures, no process)

    @Test func notificationRouting() {
        var tracker: [String: MetaTurnItemState] = [:]
        var unmapped: [String] = []
        let known: Set<String> = ["file_read"]

        // Tool start: normalized, described, unmapped recorded
        // for the unknown name.
        let started = MetaTurnNotificationRouter.route(
            method: "item/started",
            params: ["item": ["itemId": "c-1", "kind": "toolCall", "tool": "muse.read_file",
                              "args": "{\"path\": \"Sources/App.swift\"}"]],
            tracker: &tracker, unmappedToolNames: &unmapped, knownToolIDs: known, activeTurnID: "t-1")
        #expect(started.contains(.toolStarted(callID: "c-1", toolName: "file_read",
                                              argumentsJSON: "{\"path\": \"Sources/App.swift\"}", isMuseTool: true)))
        #expect(started.contains(.activity("file_read: Sources/App.swift")))
        #expect(unmapped.isEmpty) // file_read resolved via the registry

        // Tool stdout delta: tracked, never chat text.
        let delta = MetaTurnNotificationRouter.route(
            method: "item/delta",
            params: ["itemId": "c-1", "field": "output", "delta": "ok\n"],
            tracker: &tracker, unmappedToolNames: &unmapped, knownToolIDs: known, activeTurnID: "t-1")
        #expect(delta == [.toolProgress(callID: "c-1", message: "ok")])
        #expect(tracker["c-1"]?.output == "ok\n")

        // Unknown tool name is recorded exactly once.
        _ = MetaTurnNotificationRouter.route(
            method: "item/started",
            params: ["item": ["itemId": "c-2", "kind": "toolCall", "tool": "muse.future_tool", "args": "{}"]],
            tracker: &tracker, unmappedToolNames: &unmapped, knownToolIDs: known, activeTurnID: "t-1")
        #expect(unmapped == ["future_tool"])
        _ = MetaTurnNotificationRouter.route(
            method: "item/completed",
            params: ["item": ["itemId": "c-2", "kind": "toolCall", "tool": "muse.future_tool",
                              "args": "{}", "visibleOutput": "done"]],
            tracker: &tracker, unmappedToolNames: &unmapped, knownToolIDs: known, activeTurnID: "t-1")
        #expect(unmapped == ["future_tool"])

        // Text, thinking, and completion.
        var tracker2: [String: MetaTurnItemState] = ["i-1": MetaTurnItemState(kind: "agentMessage", tool: nil, args: "")]
        var unmapped2: [String] = []
        #expect(MetaTurnNotificationRouter.route(
            method: "item/delta",
            params: ["itemId": "i-1", "field": "text", "delta": "hi"],
            tracker: &tracker2, unmappedToolNames: &unmapped2, knownToolIDs: known, activeTurnID: "t-1") == [.text("hi")])
        tracker2["i-1"] = MetaTurnItemState(kind: "reasoning", tool: nil, args: "")
        #expect(MetaTurnNotificationRouter.route(
            method: "item/delta",
            params: ["itemId": "i-1", "field": "summary", "delta": "thinking…"],
            tracker: &tracker2, unmappedToolNames: &unmapped2, knownToolIDs: known, activeTurnID: "t-1") == [.thinking("thinking…")])
        #expect(MetaTurnNotificationRouter.route(
            method: "turn/completed", params: ["turnId": "t-1"],
            tracker: &tracker2, unmappedToolNames: &unmapped2, knownToolIDs: known, activeTurnID: "t-1") ==
            [.turnCompleted(turnID: "t-1")])

        // Unqueue only settles this turn; another turn's id is ignored.
        #expect(MetaTurnNotificationRouter.route(
            method: "turn/unqueued", params: ["turnId": "other"],
            tracker: &tracker2, unmappedToolNames: &unmapped2, knownToolIDs: known, activeTurnID: "t-1") == [.ignored])
        #expect(MetaTurnNotificationRouter.route(
            method: "turn/unqueued", params: ["turnId": "t-1"],
            tracker: &tracker2, unmappedToolNames: &unmapped2, knownToolIDs: known, activeTurnID: "t-1") ==
            [.turnUnqueued(turnID: "t-1")])

        // Model change and approval request.
        #expect(MetaTurnNotificationRouter.route(
            method: "session/modelChanged", params: ["modelId": "muse-spark-1.3"],
            tracker: &tracker2, unmappedToolNames: &unmapped2, knownToolIDs: known, activeTurnID: "t-1") ==
            [.modelChanged("muse-spark-1.3")])
        let approval = MetaTurnNotificationRouter.route(
            method: "approval/requested",
            params: ["sessionId": "s-1", "approvalId": "a-1", "action": "run tests"],
            tracker: &tracker2, unmappedToolNames: &unmapped2, knownToolIDs: known, activeTurnID: "t-1")
        #expect(approval == [.approvalRequested(sessionID: "s-1", approvalID: "a-1", action: "run tests", requirement: nil)])
        #expect(MetaTurnNotificationRouter.route(
            method: "approval/resolved", params: ["decision": "allow"],
            tracker: &tracker2, unmappedToolNames: &unmapped2, knownToolIDs: known, activeTurnID: "t-1") == [.ignored])
        #expect(MetaTurnNotificationRouter.route(
            method: "something/new", params: [:],
            tracker: &tracker2, unmappedToolNames: &unmapped2, knownToolIDs: known, activeTurnID: "t-1") == [.ignored])
    }

    // MARK: - Model-list / session parsing

    @Test func parseModelList() {
        let response: AnyJSON = [
            "result": ["models": [
                ["modelId": "muse-wonder-1.0", "displayLabel": "wonder", "contextLimit": 1007997],
                ["displayLabel": "no id"],
                ["modelId": "muse-spark-1.3"],
            ]],
        ]
        let models = MetaAssistTurnExecutor.parseModelList(response)
        #expect(models?.map(\.modelId) == ["muse-wonder-1.0", "muse-spark-1.3"])
        #expect(models?.first?.contextLimit == 1007997)
        #expect(models?.last?.contextLimit == 1_000_000) // Legacy default
        #expect(MetaAssistTurnExecutor.parseModelList(["result": ["models": []]]) == nil)
        #expect(MetaAssistTurnExecutor.parseModelList([:]) == nil)
    }

    @Test func parseSessionID() {
        #expect(MetaAssistTurnExecutor.parseSessionID(
            ["result": ["session": ["sessionId": "a"]]], fallback: "f") == "a")
        #expect(MetaAssistTurnExecutor.parseSessionID(
            ["session": ["sessionId": "b"]], fallback: "f") == "b")
        #expect(MetaAssistTurnExecutor.parseSessionID(
            ["sessionId": "c"], fallback: "f") == "c")
        #expect(MetaAssistTurnExecutor.parseSessionID([:], fallback: "f") == "f")
    }

    @Test func rateLimitClassification() {
        #expect(MetaAssistTurnExecutor.isRateLimitError(
            MuseCodeMSPError(code: -32000, message: "limit", kind: nil, data: ["reason": "rate_limit_exceeded"])))
        #expect(MetaAssistTurnExecutor.isRateLimitError(
            MuseCodeMSPError(code: 429, message: "Too Many Requests", kind: "quota", data: nil)))
        #expect(MetaAssistTurnExecutor.isRateLimitError(AssistantError.failed("HTTP 429: quota exceeded")))
        #expect(MetaAssistTurnExecutor.isRateLimitError(AssistantError.failed("the model is overloaded right now")))
        #expect(!MetaAssistTurnExecutor.isRateLimitError(AssistantError.failed("the host went away")))
        #expect(!MetaAssistTurnExecutor.isRateLimitError(MuseCodeCLIError.executableNotFound))
        #expect(MetaAssistTurnExecutor.isSessionNotLoaded(
            MuseCodeMSPError(code: -32000, message: "x", kind: "sessionNotLoaded", data: nil)))
        #expect(MetaAssistTurnExecutor.isSessionNotLoaded(
            AssistantError.failed("session abc is not loaded on this host")))
        #expect(!MetaAssistTurnExecutor.isSessionNotLoaded(AssistantError.failed("boom")))
    }

    @Test func effectivePrompt() {
        let history = (1...13).map { ChatMessage(.user, "turn \($0)") }
        let prompt = MetaAssistTurnExecutor.buildEffectivePrompt(
            instructions: "Be helpful.", history: history, prompt: "turn 13")
        #expect(prompt.hasPrefix("Be helpful."))
        #expect(prompt.contains("# CURRENT USER REQUEST\nturn 13"))
        // Last 12 turns only (turns 1–12; the duplicate of the
        // current prompt, "turn 13", is excluded from history and
        // appears exactly once, as the request).
        #expect(prompt.components(separatedBy: "[User]:").count - 1 == 12)
        #expect(prompt.components(separatedBy: "turn 13").count - 1 == 1)
    }

    // MARK: - Slash commands

    @Test func slashCatalog() {
        #expect(MetaSlashCommandManager.builtInCommands.count == 36)
        let ids = MetaSlashCommandManager.builtInCommands.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(MetaSlashCommandManager.builtInCommands.allSatisfy { $0.name.hasPrefix("/") })
        let manager = MetaSlashCommandManager()
        #expect(manager.searchCommands(query: "").count == 36)
        #expect(manager.searchCommands(query: "/effort").map(\.id) == ["effort"])
        #expect(manager.searchCommands(query: "model").contains { $0.id == "model" })
        #expect(manager.searchCommands(query: "no-such-command").isEmpty)
    }

    @Test func slashExecuteEffects() {
        let manager = MetaSlashCommandManager()
        let effort = manager.commands.first { $0.id == "effort" }!
        #expect(manager.executeCommand(effort, argument: "low") ==
            (text: "Meta reasoning effort set to 'low'.", effect: .setReasoningEffort("low")))
        #expect(manager.executeCommand(effort, argument: nil).effect == nil)
        let model = manager.commands.first { $0.id == "model" }!
        #expect(manager.executeCommand(model, argument: "muse-spark-1.3") ==
            (text: "Meta Assist model switched to 'muse-spark-1.3'.", effect: .setModel("muse-spark-1.3")))
        let clear = manager.commands.first { $0.id == "clear" }!
        #expect(manager.executeCommand(clear, argument: nil) ==
            (text: "Cleared Assist session.", effect: .clearSession))
        let login = manager.commands.first { $0.id == "login" }!
        #expect(manager.executeCommand(login, argument: nil) ==
            (text: "Starting Meta authentication flow...", effect: .startLogin))
        let help = manager.commands.first { $0.id == "help" }!
        #expect(manager.executeCommand(help, argument: nil) == (text: "/help", effect: .insertText("/help")))
        #expect(manager.executeCommand(help, argument: "topics") ==
            (text: "/help topics", effect: .insertText("/help topics")))
    }

    @Test func slashSkillsListParsing() {
        let output = """
            # comment line
            replica-architect\t skill\t x\t y\t Designs replica architectures
            my_skill\t skill\t x\t Short desc
            bare
            \t skill\t x\t y\t Nameless
            """
        let skills = MetaSlashCommandManager.parseSkillsList(output)
        #expect(skills.map(\.id) == ["skill-replica-architect", "skill-my_skill"])
        #expect(skills[0].title == "Replica Architect")
        #expect(skills[0].description == "Designs replica architectures")
        #expect(skills[1].description == "Short desc") // fourth field fallback
        #expect(skills[0].isTerminalSkill && skills[0].category == "Meta Skills")

        var manager = MetaSlashCommandManager()
        #expect(manager.mergeCapturedSkills(skills))
        #expect(manager.commands.count == 36 + 2)
        #expect(manager.lastCapturedAt != nil)
        #expect(!manager.mergeCapturedSkills([]))
        // A second capture replaces the old terminal skills.
        let again = MetaSlashCommandManager.parseSkillsList("only-one\t skill\t x\t y\t One\n")
        #expect(manager.mergeCapturedSkills(again))
        #expect(manager.commands.count == 36 + 1)
        #expect(manager.commands.last?.id == "skill-only-one")
    }

    @Test func slashCaptureFromTerminal() async {
        var manager = MetaSlashCommandManager()
        await manager.captureCommandsFromTerminal(executable: nil)
        #expect(manager.commands.count == 36)
        await manager.captureCommandsFromTerminal(executable: URL(fileURLWithPath: "/bin/true")) { _ in
            "fresh-skill\t skill\t x\t y\t Fresh\n"
        }
        #expect(manager.commands.count == 37)
        #expect(manager.commands.last?.id == "skill-fresh-skill")
        await manager.captureCommandsFromTerminal(executable: URL(fileURLWithPath: "/bin/true")) { _ in
            throw MuseCodeCLIError.timeout
        }
        #expect(manager.commands.count == 37) // failure keeps the catalog
    }

    // MARK: - Other models

    @Test func otherModelsResolution() {
        let discovered = [
            AssistCandidateModel(id: "gpt-4o", displayName: "GPT-4o", provider: .openAI, modelIdentifier: "gpt-4o"),
            AssistCandidateModel(id: "muse-wonder-1.0", displayName: "Meta muse-wonder-1.0",
                                 provider: .metaAssist, modelIdentifier: "muse-wonder-1.0"),
        ]
        // Meta models are excluded from the other-models list.
        let available = MuseOtherModelsBridge.availableOtherModels(discovered: discovered, cloudModelIDs: ["swiftcode-cloud:atlas"])
        #expect(available.map(\.modelIdentifier) == ["gpt-4o", "swiftcode-cloud:atlas"])
        // Free-only keeps only "free" ids, then the free fallback.
        let freeOnly = MuseOtherModelsBridge.availableOtherModels(discovered: discovered, onlyUseFree: true)
        #expect(freeOnly.map(\.modelIdentifier) == ["openrouter/free"])
        // Nothing discovered at all: the paid fallbacks.
        #expect(MuseOtherModelsBridge.availableOtherModels(discovered: []).map(\.modelIdentifier) ==
            ["gpt-4o", "gpt-4o-mini", "claude-3-7-sonnet-20250219", "gemini-2.5-pro", "gemini-2.5-flash"])

        let endpoints = [MuseCustomEndpoint(name: "Local", models: ["local-model"])]
        // Step 1: explicit selection wins.
        #expect(MuseOtherModelsBridge.resolveActiveModel(
            selectedOtherModelID: "gpt-4o", discovered: discovered, customEndpoints: endpoints) ==
            MuseOtherModelResolution(modelID: "gpt-4o", displayName: "GPT-4o", provider: "OpenAI"))
        // Step 2: first custom endpoint model.
        #expect(MuseOtherModelsBridge.resolveActiveModel(
            selectedOtherModelID: "", discovered: discovered, customEndpoints: endpoints) ==
            MuseOtherModelResolution(modelID: "local-model", displayName: "Local: local-model", provider: "Custom Model Setup"))
        // Step 3: the general model, when it is not Meta.
        #expect(MuseOtherModelsBridge.resolveActiveModel(
            selectedOtherModelID: "", generalModelID: "gpt-4o", discovered: discovered) ==
            MuseOtherModelResolution(modelID: "gpt-4o", displayName: "GPT-4o", provider: "OpenAI"))
        // Step 5: fallback when nothing is available.
        #expect(MuseOtherModelsBridge.resolveActiveModel(selectedOtherModelID: "") ==
            MuseOtherModelResolution(modelID: "gpt-4o", displayName: "OpenAI GPT-4o", provider: "OpenAI"))
        #expect(MuseOtherModelsBridge.resolveActiveModel(selectedOtherModelID: "", onlyUseFree: true) ==
            MuseOtherModelResolution(modelID: "openrouter/free", displayName: "OpenRouter Free", provider: "OpenRouter"))
    }

    @Test func thinkingTokenizer() {
        let tokenizer = MuseThinkingTokenizer()
        var thinking = ""
        var text = ""
        tokenizer.processToken("plain ", onThinkingDelta: { thinking += $0 }, onTextDelta: { text += $0 })
        tokenizer.processToken("<think>deep", onThinkingDelta: { thinking += $0 }, onTextDelta: { text += $0 })
        tokenizer.processToken(" thought", onThinkingDelta: { thinking += $0 }, onTextDelta: { text += $0 })
        tokenizer.processToken("</think>answer", onThinkingDelta: { thinking += $0 }, onTextDelta: { text += $0 })
        #expect(text == "plain answer")
        #expect(thinking == "deep thought")
        #expect(tokenizer.text == "plain <think>deep thought</think>answer")
        tokenizer.cancel()
        tokenizer.processToken("more", onThinkingDelta: { thinking += $0 }, onTextDelta: { text += $0 })
        #expect(text == "plain answer") // cancelled: nothing delivered
    }

    @Test func toolCallParser() {
        #expect(MuseToolCallParser.parse("no calls here").isEmpty)
        let text = """
            Working on it.
            ```tool_call
            {"name": "Muse.file_read", "arguments": {"path": "README.md"}}
            ```
            ```tool_call
            {"name": "not json"
            ```
            """
        let calls = MuseToolCallParser.parse(text, knownToolIDs: ["file_read"])
        #expect(calls.count == 1)
        #expect(calls[0].toolName == "file_read")
        #expect(calls[0].argumentsJSON.contains("README.md"))
    }

    @Test func otherModelsProxyCatalogAndSSE() async throws {
        let active = MuseOtherModelResolution(modelID: "gpt-4o", displayName: "OpenAI GPT-4o", provider: "OpenAI")
        let proxy = MuseLocalProxyServer()
        let url = try proxy.start(active: active, port: 0) { _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield("Hello ")
                continuation.yield("world")
                continuation.finish()
            }
        }
        defer { proxy.stop() }
        #expect(proxy.isRunning)
        #expect(proxy.activeModel == active)

        // Catalog.
        let catalogRequest = URLRequest(url: url.appendingPathComponent("/v1/models"))
        let catalog = try await HTTP.send(catalogRequest, timeout: 10)
        #expect(catalog.status == 200)
        let catalogJSON = try JSONSerialization.jsonObject(with: catalog.body) as? [String: Any]
        let data = catalogJSON?["data"] as? [[String: Any]]
        #expect(data?.first?["id"] as? String == "gpt-4o")
        let meta = (data?.first?["metadata"] as? [String: Any])?["muse-code"] as? [String: Any]
        #expect(meta?["family"] as? String == "custom-bridge")
        #expect((meta?["limit"] as? [String: Any])?["context"] as? Int == 128_000)

        // SSE translation.
        var sseRequest = URLRequest(url: url.appendingPathComponent("/responses"))
        sseRequest.httpMethod = "POST"
        sseRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sseRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": [["role": "user", "content": "Hi"]],
        ])
        let sse = try await HTTP.send(sseRequest, timeout: 10)
        #expect(sse.status == 200)
        #expect(sse.text.contains("response.output_text.delta"))
        #expect(sse.text.contains("Hello "))
        #expect(sse.text.contains("response.completed"))

        // Unknown path: 404.
        let missing = try await HTTP.send(URLRequest(url: url.appendingPathComponent("/nope")), timeout: 10)
        #expect(missing.status == 404)
    }

    // MARK: - Lifecycle (fresh bridge, sleeping fixture binary)

    @Test func lifecycleMonitoringAndRestart() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sleeper = dir.appendingPathComponent("muse")
        try "#!/bin/sh\nsleep 30\n".write(to: sleeper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sleeper.path)

        let bridge = MuseCodeMSPBridge()
        let manager = MetaAssistLifecycleManager(
            bridge: bridge,
            workspaceRoot: { dir.path },
            executable: { sleeper },
            isMetaActive: { true })
        await manager.startMonitoring()
        #expect(await manager.isMonitoring)
        await manager.stopEngine()
        #expect(await manager.stoppedIntentionally)
        // An intentional stop suppresses the restart.
        #expect(await manager.healthCheckOnce() == false)
        #expect(await manager.restartCount == 0)
        try await manager.startEngine(workspaceRoot: dir.path, executable: sleeper)
        #expect(await manager.stoppedIntentionally == false)
        #expect(await bridge.isRunning)
        // Unexpected exit: the health check restarts, once per
        // throttle window.
        await bridge.stopHost()
        #expect(await bridge.isRunning == false)
        #expect(await manager.healthCheckOnce() == true)
        #expect(await manager.restartCount == 1)
        #expect(await bridge.isRunning)
        #expect(await manager.healthCheckOnce() == false) // already running
        await manager.stopMonitoring()
        #expect(await manager.isMonitoring == false)
        await bridge.stopHost()
    }

    @Test func lifecycleWithoutExecutableIsIdle() async {
        let bridge = MuseCodeMSPBridge()
        let manager = MetaAssistLifecycleManager(bridge: bridge, isMetaActive: { true })
        try await manager.startEngine(workspaceRoot: "/tmp", executable: nil)
        #expect(await bridge.isRunning == false)
        #expect(await manager.healthCheckOnce() == false)
    }

    // MARK: - End to end against the fixture `muse`

    @Test func providerListsLiveModelsAndRunsTurn() async throws {
        guard Self.pythonAvailable() else { return }
        let (dir, _, locator) = try Self.installFakeMuse()
        defer {
            Self.clearFakeMuseEnv()
            try? FileManager.default.removeItem(at: dir)
        }
        let home = try Self.homeWithCredentials()
        defer { try? FileManager.default.removeItem(at: home) }
        let bridge = MuseCodeMSPBridge()
        let executor = MetaAssistTurnExecutor(bridge: bridge)
        let provider = MetaAssistProvider(
            locator: locator, homeDirectory: home.path,
            bridge: bridge, executor: executor)
        defer { Task { await bridge.stopHost() } }

        let availability = await provider.availability()
        guard case .ready(let models) = availability else {
            Issue.record("expected ready, got \(availability)")
            return
        }
        #expect(models.map(\.id) == ["muse-wonder-1.0"])

        let request = ChatRequest(model: "muse-wonder-1.0", instructions: "Be helpful.",
                                  messages: [ChatMessage(.user, "Say hello")],
                                  workingDirectory: dir)
        let (text, events) = try await collect(provider.send(request))
        #expect(text == "Hello world")
        #expect(events.contains(.finished(nil)))
        #expect(await executor.activeSessionID == "sess-1")
        #expect(await executor.lastTurnUnmappedToolNames.isEmpty)

        // A second turn resumes the session.
        let (text2, _) = try await collect(provider.send(request))
        #expect(text2 == "Hello world")
    }

    @Test func providerDeniesApprovalWithoutAttachment() async throws {
        guard Self.pythonAvailable() else { return }
        let (dir, log, locator) = try Self.installFakeMuse(approval: true)
        defer {
            Self.clearFakeMuseEnv()
            try? FileManager.default.removeItem(at: dir)
        }
        let home = try Self.homeWithCredentials()
        defer { try? FileManager.default.removeItem(at: home) }
        let bridge = MuseCodeMSPBridge()
        let executor = MetaAssistTurnExecutor(bridge: bridge)
        let provider = MetaAssistProvider(
            locator: locator, homeDirectory: home.path,
            bridge: bridge, executor: executor)
        defer { Task { await bridge.stopHost() } }

        let request = ChatRequest(model: "muse-wonder-1.0", instructions: "",
                                  messages: [ChatMessage(.user, "Run tests")],
                                  workingDirectory: dir)
        let (text, _) = try await collect(provider.send(request))
        #expect(text == "Hello world")
        // The host was asked, and the decision was abort: no
        // attachment means no user to ask, so deny by default.
        let logged = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(logged.contains("approval/decide"))
    }

    @Test func providerApprovalAsksAttachment() async throws {
        guard Self.pythonAvailable() else { return }
        let (dir, log, locator) = try Self.installFakeMuse(approval: true)
        defer {
            Self.clearFakeMuseEnv()
            try? FileManager.default.removeItem(at: dir)
        }
        let home = try Self.homeWithCredentials()
        defer { try? FileManager.default.removeItem(at: home) }
        let bridge = MuseCodeMSPBridge()
        let executor = MetaAssistTurnExecutor(bridge: bridge)
        let base = MetaAssistProvider(
            locator: locator, homeDirectory: home.path,
            bridge: bridge, executor: executor)
        defer { Task { await bridge.stopHost() } }

        let asked = PermissionAskedBox()
        let attachment = AgentAttachment(
            requestPermission: { title, options in
                asked.add(title, options)
                return "allow_once"
            })
        guard let provider = base.attaching(attachment) as? MetaAssistProvider else {
            Issue.record("attaching did not return a MetaAssistProvider")
            return
        }
        #expect(provider.isAttached)

        let request = ChatRequest(model: "muse-wonder-1.0", instructions: "",
                                  messages: [ChatMessage(.user, "Run tests")],
                                  workingDirectory: dir)
        let (text, _) = try await collect(provider.send(request))
        #expect(text == "Hello world")
        #expect(asked.all.count == 1)
        #expect(asked.all[0].0.contains("run tests"))
        #expect(asked.all[0].1.map(\.id) == ["allow_once", "abort"])
        let logged = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(logged.contains("approval/decide"))
    }

    @Test func providerSendFailsHonestlyWithoutBinary() async throws {
        let provider = MetaAssistProvider(locator: Self.absentLocator())
        let request = ChatRequest(model: "muse-wonder-1.0", instructions: "Be helpful.",
                                  messages: [ChatMessage(.user, "Hello")])
        do {
            for try await _ in provider.send(request) { }
            Issue.record("expected send to throw")
        } catch let error as AssistantError {
            guard case .failed(let message) = error else {
                Issue.record("expected failed, got \(error)")
                return
            }
            #expect(message.contains("muse"))
        }
    }

    @Test func providerSendFailsHonestlyWithoutCredentials() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let provider = MetaAssistProvider(locator: Self.absentLocator(), homeDirectory: dir.path)
        let request = ChatRequest(model: "muse-wonder-1.0", instructions: "",
                                  messages: [ChatMessage(.user, "Hello")])
        do {
            for try await _ in provider.send(request) { }
            Issue.record("expected send to throw")
        } catch let error as AssistantError {
            // Absent binary is checked first.
            guard case .failed(let message) = error else {
                Issue.record("expected failed, got \(error)")
                return
            }
            #expect(message.contains("muse"))
        }
    }
}
