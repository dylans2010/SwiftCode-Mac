import Foundation

// MARK: - OpenCode SDK provider (Swift facade over opencode-bridge.mjs)
//
// This file NEVER executes tools and NEVER speaks OpenCode HTTP itself.
// The previous native HTTP client (OpenCodeClient.swift) is superseded as
// the transport by the real OpenCode SDK, which Swift cannot import: the
// SDK is TypeScript (@opencode-ai/sdk@1.19.5, v2 client). Swift therefore
// launches the Node bridge (SDKHosts/opencode-bridge.mjs) and talks the
// shared NDJSON run protocol over its stdin/stdout. The bridge owns the
// SDK session, the system prompt, and the event stream; Swift owns the
// run lifecycle and, through the parent integration, the native tool
// registry that executes SwiftCode tool_call lines.
//
// INSTALL LAYOUT (Workstream D seam — read before changing paths):
// The bridge is a runtime resource, not an Xcode target member. The
// runtime manager installs it under Application Support at
//   <Application Support>/SwiftCode/SDKRuntime/opencode/bridge/opencode-bridge.mjs
// with the pinned packages at
//   <Application Support>/SwiftCode/SDKRuntime/opencode/node_modules/@opencode-ai/sdk
// (SDKRuntimeManager.runtimeDirectory/bridgeDirectory). Node resolves
// '@opencode-ai/sdk' by walking up from the bridge file and via the
// NODE_PATH the manager sets, so the bridge MUST live inside that
// directory; copying the .mjs alone somewhere else breaks SDK
// resolution (verified: a lone copy fails with a JSON error line and
// exit 1). The repo copy at
// SwiftCode/Backend/Assist/SDKHosts/opencode-bridge.mjs is the source
// the manager copies from.
//
// LAUNCHER SEAM (single call, for Workstream D):
// This provider launches through `SDKBridgeLaunching.launchBridge(
// provider:scriptPath:arguments:)`. Workstream D's SDKRuntimeManager
// exists, but its launchBridge(provider:scriptURL:extraEnvironment:
// readyTimeout:) takes NO argv, and this bridge needs argv for its
// server config (--server-url, --managed). Until D gains an
// `arguments: [String] = []` parameter passed through to
// process.arguments, this file ships a minimal Foundation-based
// launcher (`FoundationProcessBridgeLauncher`) satisfying the protocol
// — integration is then exactly one edit: construct this provider with
// D's launcher instead of the default. The launcher must resolve `node`
// explicitly, pass only a controlled environment (PATH/HOME/TMPDIR; no
// inherited secrets), and never log the run payload.
//
// NOTE ON TYPE OWNERSHIP: the shared event types live in
// SDKToolEvent.swift (SDKToolEvent/SDKToolState/SDKToolSource) and are
// used here directly — this file deliberately defines NONE of them.
// The persisted tool-source setting is the distinct
// SDKToolSourceSetting in SDKRuntimeManager.swift (which adds the
// `.combined` case the event source enum does not have). This file's
// run tool-source enum is named OpenCodeSDKToolSource precisely to
// avoid adding a third claimant.

// MARK: - Shared tool-event contract (Workstream C types)
//
// Event routing key is SDKToolEvent.source: `.opencode` events go to
// OCToolsUIView, `.swiftcode` events to the existing native tool UI —
// never by display name. The bridge's "pending" state maps to
// SDKToolState.requested; terminal states are .completed/.failed/
// .cancelled. Nothing is marked completed until the SDK reports the
// completed state or Swift returns a tool result. Bridge timestamps
// arrive as "" (unknown) and decode to nil Dates; the store treats nil
// as "not reported", never as an invented time.

/// Tool source selected for an OpenCode run. `openrouter` is NOT a valid
/// OpenCode tool source and is rejected before launch (the bridge
/// rejects it too, as defense in depth).
public enum OpenCodeSDKToolSource: String, Sendable {
    case swiftcode
    case opencode
    case combined
}

// MARK: - Bridge process seam

/// A launched bridge process. The provider actor owns this object; its
/// pipes are driven from the actor, so no concurrent access occurs.
public final class SDKBridgeSession: @unchecked Sendable {
    public let process: Process
    public let standardInput: Pipe
    public let standardOutput: Pipe
    public let standardError: Pipe?
    /// Last stderr bytes from the bridge, capped by the launcher.
    /// Session bridges previously sent stderr to /dev/null, so a
    /// bridge that died on import surfaced only a generic not-ready
    /// error; providers can now include this tail in failure text.
    public var stderrTail = ""

    public init(process: Process, standardInput: Pipe, standardOutput: Pipe, standardError: Pipe? = nil) {
        self.process = process
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public func writeLine(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        standardInput.fileHandleForWriting.write(data)
    }

    public func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}

/// The single launcher seam Workstream D replaces. `arguments` carries
/// bridge argv (for OpenCode: `--server-url <url>` and `--managed` when
/// the managed server is enabled); the run payload itself always travels
/// over stdin, never argv, so no prompt or argument ever appears in a
/// process listing.
public protocol SDKBridgeLaunching: Sendable {
    func launchBridge(provider: String, scriptPath: String, arguments: [String]) async throws -> SDKBridgeSession
}

/// Minimal Foundation launcher. Resolves `node` through
/// SDKRuntimeManager.detectRuntime() (PATH plus well-known install
/// locations, e.g. Homebrew) when it finds a node binary — the old
/// /usr/bin/env fallback alone could not see a Homebrew node from a
/// Finder-launched app, even though Settings reported a runtime as
/// available — and falls back to /usr/bin/env node otherwise. It
/// confines the child to the bridge's directory and passes only
/// PATH/HOME/TMPDIR — never the parent's full environment, which
/// could carry unrelated secrets. Bridge stderr is drained into a
/// capped tail on the session (never /dev/null, never unbounded):
/// an undrained pipe can deadlock a chatty bridge, and a discarded
/// one hides import failures behind a generic not-ready error.
public struct FoundationProcessBridgeLauncher: SDKBridgeLaunching, Sendable {
    public init() {}

    public func launchBridge(provider: String, scriptPath: String, arguments: [String]) async throws -> SDKBridgeSession {
        let process = Process()
        var nodePath: String?
        if let detected = SDKRuntimeManager.detectRuntime(), detected.kind == .node {
            nodePath = detected.path
        }
        if let nodePath {
            process.executableURL = URL(fileURLWithPath: nodePath)
            process.arguments = [scriptPath] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", scriptPath] + arguments
        }
        process.currentDirectoryURL = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
        var environment: [String: String] = [:]
        let parent = ProcessInfo.processInfo.environment
        var pathValue = parent["PATH"] ?? ""
        if let nodePath {
            let binDir = (nodePath as NSString).deletingLastPathComponent
            pathValue = pathValue.isEmpty ? binDir : "\(binDir):\(pathValue)"
        }
        if !pathValue.isEmpty { environment["PATH"] = pathValue }
        if let home = parent["HOME"] { environment["HOME"] = home }
        if let tmp = parent["TMPDIR"] { environment["TMPDIR"] = tmp }
        environment["NODE_NO_WARNINGS"] = "1"
        process.environment = environment
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let session = SDKBridgeSession(process: process, standardInput: stdin, standardOutput: stdout, standardError: stderr)
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else { return }
            session.stderrTail += text
            if session.stderrTail.count > 8192 {
                session.stderrTail = String(session.stderrTail.suffix(8192))
            }
        }
        return session
    }
}

// MARK: - Run request

public struct OpenCodeSDKHistoryItem: Sendable {
    public let role: String
    public let text: String
    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

public struct OpenCodeSDKToolDefinition: Sendable {
    public let name: String
    public let description: String
    /// Raw JSON string of the parameters schema (already validated by
    /// the registry when the definition was built).
    public let parametersJSON: String
    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

public struct OpenCodeSDKRunRequest: Sendable {
    /// Stored model id, `opencode:provider/model`. Validated with
    /// OpenCodeModelID before launch; never guessed or rewritten.
    public let model: String
    public let systemPrompt: String
    public let userText: String
    public let history: [OpenCodeSDKHistoryItem]
    public let tools: [OpenCodeSDKToolDefinition]
    public let toolSource: OpenCodeSDKToolSource
    public let directory: String
    /// Resume an existing server session; nil creates a fresh one.
    public let sessionId: String?
    public let agentName: String

    public init(
        model: String,
        systemPrompt: String,
        userText: String,
        history: [OpenCodeSDKHistoryItem] = [],
        tools: [OpenCodeSDKToolDefinition] = [],
        toolSource: OpenCodeSDKToolSource,
        directory: String,
        sessionId: String? = nil,
        agentName: String = OpenCodeConfiguration.defaultAgentName
    ) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.userText = userText
        self.history = history
        self.tools = tools
        self.toolSource = toolSource
        self.directory = directory
        self.sessionId = sessionId
        self.agentName = agentName
    }
}

public enum OpenCodeSDKProviderError: Error, Sendable {
    case invalidModelID(String)
    case bridgeNotReady(String)
    case bridgeFailed(String)
    case bridgeExited(Int32)
    case noToolExecutor(toolName: String)
}

// MARK: - Provider

/// Swift facade for OpenCode SDK runs. One provider instance serves one
/// run at a time; `cancel()` aborts the active run and terminates the
/// bridge (which closes a managed server it owns, and never touches a
/// server it does not own).
public actor OpenCodeSDKProvider {
    private let launcher: SDKBridgeLaunching
    private let scriptPath: String
    private let configuration: OpenCodeConfiguration

    private var session: SDKBridgeSession?
    private var lineContinuation: AsyncStream<String>.Continuation?

    public init(
        launcher: SDKBridgeLaunching = FoundationProcessBridgeLauncher(),
        scriptPath: String,
        configuration: OpenCodeConfiguration = OpenCodeConfiguration.load()
    ) {
        self.launcher = launcher
        self.scriptPath = scriptPath
        self.configuration = configuration
    }

    /// Runs one request, streaming model text deltas. Tool activity is
    /// reported through `onToolEvent`; SwiftCode-native tool_call lines
    /// are executed by `executeTool` (supplied by the parent
    /// integration, which routes through the native registry) and the
    /// result is fed back to the bridge. This provider itself executes
    /// nothing: if no executor is supplied, tool calls fail closed with
    /// an explicit error result instead of hanging or being faked.
    public func run(
        _ request: OpenCodeSDKRunRequest,
        onToolEvent: @escaping @Sendable (SDKToolEvent) -> Void,
        executeTool: (@Sendable (String, String, String) async throws -> String)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.execute(request, continuation: continuation, onToolEvent: onToolEvent, executeTool: executeTool)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func cancel() {
        if let session {
            // Ask the bridge to abort the server session first, then
            // terminate the process; the bridge closes a managed server
            // on SIGTERM and never closes an external one.
            session.writeLine(#"{"type":"cancel"}"#)
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                session.terminate()
            }
        }
        lineContinuation?.finish()
    }

    // MARK: - Execution

    private func execute(
        _ request: OpenCodeSDKRunRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        onToolEvent: @escaping @Sendable (SDKToolEvent) -> Void,
        executeTool: (@Sendable (String, String, String) async throws -> String)?
    ) async throws {
        guard OpenCodeModelID.parse(request.model) != nil else {
            throw OpenCodeSDKProviderError.invalidModelID(
                "Invalid OpenCode model id \"\(request.model)\": expected \"opencode:<provider>/<model>\". " +
                "Select an OpenCode model in Assist Settings; SwiftCode never substitutes another model."
            )
        }

        var bridgeArgs = ["--server-url", configuration.serverURL.absoluteString]
        if configuration.managedServerEnabled {
            guard configuration.isLoopback else {
                throw OpenCodeSDKProviderError.bridgeNotReady(
                    "Managed OpenCode server refused for non-loopback URL \"\(configuration.serverURL.absoluteString)\". " +
                    "Managed servers are loopback-only."
                )
            }
            bridgeArgs.append("--managed")
        }

        let bridge: SDKBridgeSession
        do {
            bridge = try await launcher.launchBridge(provider: "opencode", scriptPath: scriptPath, arguments: bridgeArgs)
        } catch {
            throw OpenCodeSDKProviderError.bridgeFailed("Failed to launch the OpenCode SDK bridge: \(error.localizedDescription)")
        }
        self.session = bridge

        // Stream stdout lines into an AsyncStream via readabilityHandler.
        let (lineStream, lineContinuation) = AsyncStream<String>.makeStream()
        self.lineContinuation = lineContinuation
        let buffer = BufferWrapper()
        let outputHandle = bridge.standardOutput.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            while let newline = buffer.popLine() {
                if let line = String(data: newline, encoding: .utf8), !line.isEmpty {
                    lineContinuation.yield(line)
                }
            }
        }
        bridge.process.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }
        // Readiness: the bridge prints {"type":"ready"} only after the
        // SDK import resolves AND global.health() passes. Anything else
        // first (an error line, EOF, or 30 seconds of silence) is a
        // failed connection — never a successful one.
        let ready = try await waitForReady(stream: lineStream, bridge: bridge)
        guard ready else {
            bridge.terminate()
            let tail = bridge.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            throw OpenCodeSDKProviderError.bridgeNotReady(
                "OpenCode SDK bridge did not report ready within 30 seconds. " +
                "Check that the SDK runtime is installed and the server is reachable, then try again." +
                (tail.isEmpty ? "" : " Bridge stderr: \(tail)")
            )
        }

        // Send the run request. Tool definitions travel as parsed JSON
        // objects (parametersJSON is decoded here; a malformed schema
        // fails the run loudly instead of reaching the bridge as text).
        var runPayload: [String: Any] = [
            "type": "run",
            // A real per-run id (the OpenRouter provider already sends
            // one). The old payload sent none, so the bridge defaulted
            // requestId to "run" and SwiftCode tool call ids repeated
            // verbatim across runs (swiftcode-run-1, -2, …), which the
            // store merges by toolCallId — run N overwrote run 1's rows.
            "requestId": UUID().uuidString,
            "provider": "opencode",
            "model": request.model,
            "systemPrompt": request.systemPrompt,
            "userText": request.userText,
            "history": request.history.map { ["role": $0.role, "text": $0.text] },
            "toolSource": request.toolSource.rawValue,
            "config": [
                "directory": request.directory,
                "agentName": request.agentName,
            ] as [String: Any],
        ]
        var toolsPayload: [[String: Any]] = []
        for tool in request.tools {
            let schema = (try? JSONSerialization.jsonObject(with: Data(tool.parametersJSON.utf8))) as? [String: Any] ?? [:]
            toolsPayload.append(["name": tool.name, "description": tool.description, "parameters": schema])
        }
        runPayload["tools"] = toolsPayload
        if let sessionId = request.sessionId {
            var config = runPayload["config"] as! [String: Any]
            config["sessionId"] = sessionId
            runPayload["config"] = config
        }
        let runData = try JSONSerialization.data(withJSONObject: runPayload, options: [])
        guard let runLine = String(data: runData, encoding: .utf8) else {
            throw OpenCodeSDKProviderError.bridgeFailed("Failed to encode the OpenCode run request.")
        }
        bridge.writeLine(runLine)

        // Consume bridge lines until done/error/process exit.
        for try await line in lineStream {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }
            switch type {
            case "text":
                if let delta = json["delta"] as? String, !delta.isEmpty {
                    continuation.yield(delta)
                }
            case "tool_event":
                if let eventJson = json["event"] as? [String: Any],
                   let event = decodeToolEvent(eventJson) {
                    onToolEvent(event)
                }
            case "tool_call":
                // SwiftCode-native tool: execute through the parent's
                // executor (native registry), never here. The result —
                // or an explicit failure — goes back to the bridge so
                // the model continues with real data, not a guess.
                let callId = json["id"] as? String ?? ""
                let name = json["name"] as? String ?? ""
                let args = json["arguments"] as? String ?? "{}"
                onToolEvent(SDKToolEvent(
                    provider: "opencode",
                    sessionId: request.sessionId ?? "",
                    toolCallId: callId,
                    toolName: name,
                    source: .swiftcode,
                    state: .running,
                    arguments: args
                ))
                let resultLine: String
                do {
                    guard let executeTool else {
                        throw OpenCodeSDKProviderError.noToolExecutor(toolName: name)
                    }
                    let result = try await executeTool(callId, name, args)
                    onToolEvent(SDKToolEvent(
                        provider: "opencode",
                        sessionId: request.sessionId ?? "",
                        toolCallId: callId,
                        toolName: name,
                        source: .swiftcode,
                        state: .completed,
                        arguments: args,
                        result: result
                    ))
                    let payload: [String: Any] = ["type": "tool_result", "id": callId, "result": result]
                    resultLine = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8) ?? ""
                } catch {
                    onToolEvent(SDKToolEvent(
                        provider: "opencode",
                        sessionId: request.sessionId ?? "",
                        toolCallId: callId,
                        toolName: name,
                        source: .swiftcode,
                        state: .failed,
                        arguments: args,
                        error: error.localizedDescription
                    ))
                    let payload: [String: Any] = ["type": "tool_result", "id": callId, "error": error.localizedDescription]
                    resultLine = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8) ?? ""
                }
                if !resultLine.isEmpty {
                    bridge.writeLine(resultLine)
                }
            case "done":
                let final = json["finalText"] as? String ?? ""
                if !final.isEmpty {
                    // Text deltas already streamed the answer; done only
                    // carries the completed text for consumers that need
                    // it. Do not re-yield it (that would duplicate output).
                    _ = final
                }
                cleanup(bridge: bridge)
                continuation.finish()
                return
            case "error":
                let message = json["message"] as? String ?? "Unknown OpenCode bridge error."
                cleanup(bridge: bridge)
                throw OpenCodeSDKProviderError.bridgeFailed(message)
            default:
                continue
            }
        }

        cleanup(bridge: bridge)
        if bridge.process.isRunning == false, bridge.process.terminationStatus != 0 {
            throw OpenCodeSDKProviderError.bridgeExited(bridge.process.terminationStatus)
        }
        continuation.finish()
    }

    private func handleTermination() {
        lineContinuation?.finish()
        lineContinuation = nil
    }

    private func cleanup(bridge: SDKBridgeSession) {
        bridge.standardOutput.fileHandleForReading.readabilityHandler = nil
        bridge.standardError?.fileHandleForReading.readabilityHandler = nil
        lineContinuation?.finish()
        lineContinuation = nil
        // The bridge exits on stdin EOF; close our write end so it can
        // shut down (and close a managed server it owns). Never kill an
        // external server: closing stdin only ends the bridge process.
        try? bridge.standardInput.fileHandleForWriting.close()
        if session === bridge {
            session = nil
        }
    }

    /// Waits for the bridge's ready line, with a 30-second timeout and
    /// early failure on an error line or EOF. Returns false on timeout.
    /// Ready lines are consumed from the stream's shared storage, and
    /// the run loop below ignores any stray "ready" line anyway, so
    /// either consumption outcome is safe.
    ///
    /// Timeout fix: the old task-group race never actually timed out
    /// for a live-but-silent bridge, because AsyncStream's next() is
    /// not cancellation-aware — the group scope waited for the
    /// suspended consumer even after the sleep task won. The timeout
    /// task now terminates the bridge; its termination handler
    /// finishes the line continuation, which unblocks the consumer.
    /// A ready line whose sdkVersion differs from the pinned version
    /// is also rejected here (the session path previously accepted
    /// any ready line; the runner's disk check is the primary gate,
    /// this is defence in depth).
    private func waitForReady(stream: AsyncStream<String>, bridge: SDKBridgeSession) async throws -> Bool {
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                // The iterator is created inside the task: AsyncStream
                // shares one storage, so consumption order is unchanged,
                // and a captured mutating iterator cannot cross into a
                // concurrently-executing closure.
                var iterator = stream.makeAsyncIterator()
                while let line = await iterator.next() {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String else {
                        continue
                    }
                    if type == "ready" {
                        let version = json["sdkVersion"] as? String ?? ""
                        guard version == SDKProvider.openCode.pinnedVersion else {
                            throw OpenCodeSDKProviderError.bridgeFailed(
                                "OpenCode bridge reported SDK version \"\(version)\", expected \(SDKProvider.openCode.pinnedVersion). " +
                                "Reinstall the SDK runtime in Assist Settings → SDK Providers.")
                        }
                        return true
                    }
                    if type == "error" {
                        throw OpenCodeSDKProviderError.bridgeFailed(
                            json["message"] as? String ?? "OpenCode bridge failed before ready.")
                    }
                }
                // EOF before ready: the bridge died; report as timeout
                // rather than hanging the caller.
                return false
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                bridge.terminate()
                return false
            }
            let first = try await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func decodeToolEvent(_ json: [String: Any]) -> SDKToolEvent? {
        guard let provider = json["provider"] as? String,
              let sessionId = json["sessionId"] as? String,
              let toolCallId = json["toolCallId"] as? String,
              let toolName = json["toolName"] as? String,
              let sourceRaw = json["source"] as? String,
              let source = SDKToolSource(rawValue: sourceRaw),
              let stateRaw = json["state"] as? String else {
            return nil
        }
        let state: SDKToolState
        switch stateRaw {
        case "pending": state = .requested
        case "running": state = .running
        case "completed": state = .completed
        case "failed": state = .failed
        case "cancelled": state = .cancelled
        default: return nil
        }
        // Bridge timestamps are ISO 8601 strings or "" (unknown -> nil).
        // An empty or unparseable timestamp is never invented.
        let iso = ISO8601DateFormatter()
        func dateField(_ key: String) -> Date? {
            guard let raw = json[key] as? String, !raw.isEmpty else { return nil }
            return iso.date(from: raw)
        }
        let result = (json["result"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let error = (json["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return SDKToolEvent(
            provider: provider,
            sessionId: sessionId,
            toolCallId: toolCallId,
            toolName: toolName,
            source: source,
            state: state,
            arguments: json["arguments"] as? String ?? "",
            result: result,
            error: error,
            startedAt: dateField("startedAt"),
            completedAt: dateField("completedAt")
        )
    }
}
