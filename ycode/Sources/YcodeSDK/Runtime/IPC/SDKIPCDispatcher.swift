import Foundation
import YcodeExtensions

// MARK: - SDKRuntimeSessionInfo
//
// Minimal session identity for one extension runtime. The dropped
// `SDKRuntimeSession` state machine stays dropped (spec §3.2/§3.4):
// this is a value, not a lifecycle — the v2 host owns the runtime
// lifecycle, and the dispatcher owns one session's worth of routing
// state (build handles, registered commands) keyed by it.
//
// The presented API key secret is toxic: it is held only for the
// session's lifetime, re-verified on every request, and never logged.

public struct SDKRuntimeSessionInfo: Sendable {
    public let extensionID: String
    /// SHA-256 package digest of the running install.
    public let packageDigest: String
    public let projectRootPath: String
    /// The session-presented developer API key secret, if any.
    public let presentedAPIKey: String?

    public init(extensionID: String, packageDigest: String, projectRootPath: String, presentedAPIKey: String? = nil) {
        self.extensionID = extensionID
        self.packageDigest = packageDigest
        self.projectRootPath = projectRootPath
        self.presentedAPIKey = presentedAPIKey
    }
}

// MARK: - SDKCommandDefinition
//
// Wire type for `commands.register`. The dropped `SDKCommandRegistry`
// stays dropped (v2 `NativePluginRegistry` + the MCP catalogue own
// command execution); the dispatcher keeps a per-session table of
// these definitions only, with Legacy's validation: kebab-case IDs,
// titles 1–128 characters, max 64 commands per session, per-session
// ownership (an unregister for an unknown ID is a silent no-op).

public struct SDKCommandDefinition: Sendable, Codable, Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    /// Validates a command definition. IDs are kebab-case
    /// (`^[a-z][a-z0-9-]{0,63}$`); titles are 1–128 trimmed characters.
    public static func validate(id: String, title: String) throws -> SDKCommandDefinition {
        guard id.count <= 64,
              id.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil else {
            throw SDKError(code: .invalidArgument, message: "The command ID must be kebab-case (e.g. \"my-command\").")
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...128).contains(trimmedTitle.count) else {
            throw SDKError(code: .invalidArgument, message: "The command title must be 1–128 characters.")
        }
        return SDKCommandDefinition(id: id, title: trimmedTitle)
    }
}

// MARK: - SDKIPCDispatcher
//
// Ported from Legacy `SwiftCode/SDK/Runtime/IPC/SDKIPCDispatcher.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Routes IPC requests for one extension runtime session. One
// dispatcher per `SDKRuntimeSessionInfo`.
//
// Pipeline (per request):
//  1. Peek the envelope: protocol version must be 1
//     (`.ipcProtocolMismatch`), the frame must be a `.request`
//     (`.ipcMalformed`), 1 MiB bound (`.resourceLimitExceeded`).
//  2. `SDKAssistGate.check` FIRST — before routing or decoding.
//  3. Re-verify the session API key on EVERY request (fail closed).
//  4. Build `SDKCallerIdentity` from the SESSION, never the payload.
//  5. Route inside a 60s timeout (detached watchdog; on timeout the
//     operation keeps running detached and the caller gets
//     `.ipcTimeout`).
//
// `dispatch` never throws: every failure becomes an `ok: false`
// response carrying an `SDKErrorPayload`.
//
// TRANSPORT: the dropped `SDKIPCTransport` stays dropped (v2
// `ExtensionRPC` is the one wire protocol). The dispatcher takes
// `Data` in and returns `Data` out; the caller owns the transport and
// installs `eventSink` to receive unsolicited events (build output,
// Assist stream deltas). With no sink installed, events are dropped —
// the host runtime must install one.

public actor SDKIPCDispatcher {
    /// Per-request timeout (60s).
    public static let requestTimeout: TimeInterval = 60
    /// Maximum commands per session.
    public static let maxCommandsPerSession = 64

    private let session: SDKRuntimeSessionInfo
    /// Receives unsolicited event frames (build output, Assist stream).
    public var eventSink: (@Sendable (Data) -> Void)?

    private var buildHandles: [UUID: SDKBuildHandle] = [:]
    private var commands: [String: SDKCommandDefinition] = [:]

    public init(session: SDKRuntimeSessionInfo, eventSink: (@Sendable (Data) -> Void)? = nil) {
        self.session = session
        self.eventSink = eventSink
    }

    // MARK: - Entry point

    /// Dispatches one IPC frame and returns the response frame. Never
    /// throws: failures become `ok: false` responses.
    public func dispatch(_ data: Data) async -> Data {
        // Peek the frame type first (1 MiB bound enforced here).
        let messageType: SDKMessageType
        do {
            messageType = try SDKIPCCodec.decodeEnvelopeType(from: data)
        } catch let error as SDKError {
            return errorResponse(requestId: "", error: error)
        } catch {
            return errorResponse(requestId: "", error: SDKError(code: .ipcMalformed, message: "Message is not a valid SDK IPC envelope."))
        }
        guard messageType == .request else {
            return errorResponse(requestId: "", error: SDKError(code: .ipcMalformed, message: "Expected a request frame."))
        }

        // Best-effort requestId + protocol version.
        let peek: EnvelopePeek
        do {
            peek = try JSONDecoder().decode(EnvelopePeek.self, from: data)
        } catch {
            return errorResponse(requestId: "", error: SDKError(code: .ipcMalformed, message: "Message is not a valid SDK IPC envelope."))
        }
        guard peek.protocolVersion == SDKIPCCodec.sdkProtocolVersion else {
            return errorResponse(
                requestId: peek.requestId,
                error: SDKError(code: .ipcProtocolMismatch, message: "Unsupported SDK protocol version \(peek.protocolVersion).")
            )
        }

        let envelope: SDKRequestEnvelope<JSONValue>
        do {
            envelope = try JSONDecoder().decode(SDKRequestEnvelope<JSONValue>.self, from: data)
        } catch {
            return errorResponse(requestId: peek.requestId, error: SDKError(code: .ipcMalformed, message: "The request payload could not be decoded."))
        }

        do {
            // 2. Assist gate FIRST — before routing or decoding.
            try await SDKAssistGate.check(ipcMethod: envelope.method, callerExtensionID: session.extensionID)
            // 3. Re-verify the session key on every request.
            let key = try await verifySessionAPIKey()
            // 4. Caller identity comes from the SESSION, never the payload.
            let caller = SDKCallerIdentity(
                extensionID: session.extensionID,
                packageDigest: session.packageDigest,
                projectRootPath: session.projectRootPath,
                apiKey: key
            )
            // 5. Route inside the 60s timeout.
            let payload = try await routeWithTimeout(method: envelope.method, payload: envelope.payload, requestId: envelope.requestId, caller: caller)
            return SDKIPCCodec.encodeResponse(SDKResponseEnvelope(requestId: envelope.requestId, payload: payload))
        } catch let error as SDKError {
            return errorResponse(requestId: envelope.requestId, error: error)
        } catch {
            return errorResponse(requestId: envelope.requestId, error: SDKError(code: .serviceUnavailable, message: "The request could not be completed."))
        }
    }

    /// Sends an unsolicited event frame to the installed sink (dropped
    /// when no sink is installed).
    public func event(name: String, payload: JSONValue, requestId: String) {
        guard let eventSink else { return }
        let envelope = SDKEventEnvelope(requestId: requestId, event: name, payload: payload)
        eventSink(SDKIPCCodec.encodeEvent(envelope))
    }

    // MARK: - Pipeline helpers

    private struct EnvelopePeek: Decodable {
        let protocolVersion: Int
        let requestId: String
    }

    private func errorResponse(requestId: String, error: SDKError) -> Data {
        SDKIPCCodec.encodeResponse(SDKResponseEnvelope<JSONValue>(requestId: requestId, error: SDKErrorPayload(from: error)))
    }

    private func verifySessionAPIKey() async throws -> SDKAPIKey? {
        guard let secret = session.presentedAPIKey else { return nil }
        // `SDKAPIKeyStore.verify` audits auth failures itself; the
        // dispatcher just fails closed on any verification error.
        return try await SDKAPIKeyStore.shared.verify(secret: secret)
    }

    private func routeWithTimeout(method: String, payload: JSONValue, requestId: String, caller: SDKCallerIdentity) async throws -> JSONValue {
        let routeTask = Task { try await self.route(method: method, payload: payload, requestId: requestId, caller: caller) }
        return try await withThrowingTaskGroup(of: JSONValue.self) { group in
            group.addTask { try await routeTask.value }
            group.addTask {
                try await Task.sleep(for: .seconds(Self.requestTimeout))
                throw SDKError(code: .ipcTimeout, message: "The extension request timed out.")
            }
            guard let value = try await group.next() else {
                throw SDKError(code: .serviceUnavailable, message: "The request produced no result.")
            }
            group.cancelAll()
            // The route task keeps running detached when the timeout
            // won the race (its result is simply dropped).
            return value
        }
    }

    // MARK: - Routing

    private func route(method: String, payload: JSONValue, requestId: String, caller: SDKCallerIdentity) async throws -> JSONValue {
        switch method {
        case "sourceControl.getStatus":
            return try encodeJSON(try await SDKSourceControlAdapter.shared.getStatus(caller: caller))
        case "sourceControl.getDiff":
            let options = try decodePayload(payload, as: SDKDiffOptions.self)
            return try encodeJSON(try await SDKSourceControlAdapter.shared.getDiff(caller: caller, options: options))
        case "build.run":
            let request = try decodePayload(payload, as: SDKBuildRequest.self)
            let handle = try await SDKBuildService.shared.run(caller: caller, request: request)
            buildHandles[handle.id] = handle
            forwardBuildEvents(handle: handle, requestId: requestId)
            return try encodeJSON(["handleId": handle.id.uuidString, "correlationId": await handle.correlationId])
        case "build.wait":
            let handle = try buildHandle(from: payload)
            return try encodeJSON(try await handle.wait())
        case "build.cancel":
            let handle = try buildHandle(from: payload)
            await handle.cancel()
            return .bool(true)
        case "cloudModel.complete":
            let request = try decodePayload(payload, as: SDKCloudModelCompletionRequest.self)
            let text = try await SDKCloudModelAdapter.shared.complete(caller: caller, request: request)
            return .string(text)
        case "assist.invoke":
            return try await routeAssistInvoke(payload: payload, requestId: requestId, caller: caller)
        case "terminalSandbox.run":
            let request = try decodePayload(payload, as: SDKSandboxRunRequest.self)
            return try encodeJSON(try await SDKSandboxedTerminal.shared.run(caller: caller, request: request))
        case "security.addValue":
            let request = try decodePayload(payload, as: SDKSecurityAddRequest.self)
            return try encodeJSON(try await SDKSecurityService.shared.addValue(caller: caller, request: request))
        case "security.hasValue":
            let request = try decodePayload(payload, as: SDKSecurityLookupRequest.self)
            return try encodeJSON(try await SDKSecurityService.shared.hasValue(caller: caller, request: request))
        case "security.listValueIDs":
            let request = try decodePayload(payload, as: SDKSecurityListRequest.self)
            return try encodeJSON(try await SDKSecurityService.shared.listValueIDs(caller: caller, request: request))
        case "security.deleteValue":
            let request = try decodePayload(payload, as: SDKSecurityLookupRequest.self)
            try await SDKSecurityService.shared.deleteValue(caller: caller, request: request)
            return .bool(true)
        case "security.useValue":
            let request = try decodePayload(payload, as: SDKSecurityUseRequest.self)
            return try encodeJSON(try await SDKSecurityService.shared.useValue(caller: caller, request: request))
        case "commands.register":
            try await SDKCapabilityBroker.authorize(.uiContribute, for: caller)
            let definition = try decodePayload(payload, as: SDKCommandDefinition.self)
            let validated = try SDKCommandDefinition.validate(id: definition.id, title: definition.title)
            guard commands.count < Self.maxCommandsPerSession else {
                throw SDKError(code: .resourceLimitExceeded, message: "Too many registered commands (max \(Self.maxCommandsPerSession)).")
            }
            guard commands[validated.id] == nil else {
                throw SDKError(code: .invalidArgument, message: "The command is already registered.")
            }
            commands[validated.id] = validated
            return try encodeJSON(validated)
        case "commands.unregister":
            let id = try stringField(payload, "id")
            commands.removeValue(forKey: id) // Unknown ID: silent no-op.
            return .bool(true)
        case "ui.openView":
            return try await routeOpenView(payload: payload, caller: caller)
        case "log.debug", "log.info":
            let message = try decodeLogMessage(payload, level: .info)
            SDKUserLogger.shared.logInfo(message.message, title: message.title, correlationId: message.correlationId)
            return .bool(true)
        case "log.warn":
            let message = try decodeLogMessage(payload, level: .warning)
            SDKUserLogger.shared.logWarning(message.message, title: message.title, correlationId: message.correlationId)
            return .bool(true)
        case "log.error":
            let message = try decodeLogMessage(payload, level: .error)
            SDKUserLogger.shared.logError(message.message, title: message.title, correlationId: message.correlationId)
            return .bool(true)
        default:
            throw SDKError(code: .invalidArgument, message: "Unknown IPC method: \(method).")
        }
    }

    // MARK: - Build events

    private func forwardBuildEvents(handle: SDKBuildHandle, requestId: String) {
        Task.detached {
            let stream = await handle.events
            for await outputEvent in stream {
                let payload = (try? await self.encodeJSON(outputEvent)) ?? .null
                await self.event(name: "build.output", payload: payload, requestId: requestId)
            }
            let result = await handle.wait()
            if let payload = try? await self.encodeJSON(result) {
                await self.event(name: "build.finished", payload: payload, requestId: requestId)
            }
            await self.removeBuildHandle(handle.id)
        }
    }

    private func removeBuildHandle(_ id: UUID) {
        buildHandles.removeValue(forKey: id)
    }

    private func buildHandle(from payload: JSONValue) throws -> SDKBuildHandle {
        let idString = try stringField(payload, "handleId")
        guard let id = UUID(uuidString: idString), let handle = buildHandles[id] else {
            throw SDKError(code: .invalidArgument, message: "The build handle does not exist.")
        }
        // Possession of the handle IS the authorization — handles live
        // in this session's map only, so a foreign handle cannot be
        // named here.
        return handle
    }

    // MARK: - Assist invoke

    private func routeAssistInvoke(payload: JSONValue, requestId: String, caller: SDKCallerIdentity) async throws -> JSONValue {
        guard let key = caller.apiKey else {
            throw await SDKAssistGate.deny(callerExtensionID: caller.extensionID, route: "assist.invoke")
        }
        try await SDKAssistService.shared.requireAssistEntitlement(key: key, extensionID: caller.extensionID)
        let op = try stringField(payload, "op")
        switch op {
        case "session.create":
            let options = SDKAssistSessionOptions(
                title: (try? optionalStringField(payload, "title")).flatMap { $0 },
                systemPrompt: (try? optionalStringField(payload, "systemPrompt")).flatMap { $0 },
                model: (try? optionalStringField(payload, "model")).flatMap { $0 }
            )
            let session = try await SDKAssistService.shared.createSession(key: key, extensionID: caller.extensionID, options: options)
            return try encodeJSON(session)
        case "session.list":
            let sessions = await SDKAssistService.shared.listSessions(forExtensionID: caller.extensionID)
            return try encodeJSON(sessions)
        case "message.send":
            let sessionID = try sessionIDField(payload)
            let message = try stringField(payload, "message")
            let response = try await SDKAssistService.shared.send(sessionID: sessionID, key: key, extensionID: caller.extensionID, message: message)
            return try encodeJSON(response)
        case "message.stream":
            let sessionID = try sessionIDField(payload)
            let message = try stringField(payload, "message")
            let stream = await SDKAssistService.shared.sendStreaming(sessionID: sessionID, key: key, extensionID: caller.extensionID, message: message)
            Task.detached {
                do {
                    for try await streamEvent in stream {
                        switch streamEvent {
                        case .started:
                            break
                        case .delta(let text):
                            await self.event(name: "assist.stream", payload: .object(["delta": .string(text), "done": .bool(false)]), requestId: requestId)
                        case .completed:
                            await self.event(name: "assist.stream", payload: .object(["delta": .string(""), "done": .bool(true)]), requestId: requestId)
                        case .failed(let error):
                            await self.event(name: "assist.stream", payload: .object(["error": .string(error.message), "done": .bool(true)]), requestId: requestId)
                        }
                    }
                } catch {
                    let message = (error as? SDKError)?.message ?? error.localizedDescription
                    await self.event(name: "assist.stream", payload: .object(["error": .string(message), "done": .bool(true)]), requestId: requestId)
                }
            }
            return .object(["streaming": .bool(true), "sessionId": .string(sessionID.uuidString)])
        case "tool.invoke":
            let sessionID = try sessionIDField(payload)
            let toolName = try stringField(payload, "toolName")
            let arguments = (try? payload.objectValue?["arguments"]?.objectValue?.compactMapValues { $0.stringValue }) ?? [:]
            let call = SDKAssistToolCall(toolName: toolName, arguments: arguments)
            let result = try await SDKAssistService.shared.executeTool(sessionID: sessionID, key: key, extensionID: caller.extensionID, call: call)
            return try encodeJSON(result)
        case "session.close":
            let sessionID = try sessionIDField(payload)
            try await SDKAssistService.shared.closeSession(id: sessionID, extensionID: caller.extensionID)
            return .bool(true)
        default:
            throw SDKError(code: .invalidArgument, message: "Unknown assist operation: \(op).")
        }
    }

    // MARK: - Open view

    private func routeOpenView(payload: JSONValue, caller: SDKCallerIdentity) async throws -> JSONValue {
        let viewID = try stringField(payload, "viewId")
        // `assist.main` is carved out to the entitled Assist opener.
        if viewID == SDKAssistUIOpener.assistMainViewID {
            try await SDKAssistUIOpener.openAssistView(caller: caller)
            return .bool(true)
        }
        guard let entry = ScopesIDLists.byId[viewID] else {
            throw SDKError(code: .unknownCapability, message: "Unknown view: \(viewID).")
        }
        try await SDKCapabilityBroker.authorize(entry.capabilityId, for: caller)
        try await SDKViewOpener.shared.open(viewID: viewID)
        return .bool(true)
    }

    // MARK: - Payload helpers

    /// Decodes a payload through a JSON round-trip. Malformed payloads
    /// become `.invalidArgument`, never a crash.
    private func decodePayload<T: Decodable>(_ payload: JSONValue, as type: T.Type) throws -> T {
        do {
            let data = try JSONEncoder().encode(payload)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SDKError(code: .invalidArgument, message: "The request payload is malformed.")
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func stringField(_ payload: JSONValue, _ name: String) throws -> String {
        guard let value = payload.objectValue?[name]?.stringValue, !value.isEmpty else {
            throw SDKError(code: .invalidArgument, message: "The request is missing the “\(name)” field.")
        }
        return value
    }

    private func optionalStringField(_ payload: JSONValue, _ name: String) throws -> String? {
        guard let raw = payload.objectValue?[name], raw != .null else { return nil }
        guard let value = raw.stringValue else {
            throw SDKError(code: .invalidArgument, message: "The “\(name)” field must be a string.")
        }
        return value
    }

    private func sessionIDField(_ payload: JSONValue) throws -> UUID {
        let raw = try stringField(payload, "sessionId")
        guard let id = UUID(uuidString: raw) else {
            throw SDKError(code: .invalidArgument, message: "The session ID is invalid.")
        }
        return id
    }

    /// A log message from an extension. The message is sanitized by
    /// `SDKUserLogger` on delivery — never logged raw.
    private struct ExtensionLogMessage {
        let level: SDKUserLogLevel
        let title: String
        let message: String
        let correlationId: String?
    }

    private func decodeLogMessage(_ payload: JSONValue, level: SDKUserLogLevel) throws -> ExtensionLogMessage {
        let message = try stringField(payload, "message")
        let title = (try? optionalStringField(payload, "title")) ?? "Extension log"
        let correlationId = try? optionalStringField(payload, "correlationId")
        return ExtensionLogMessage(level: level, title: title, message: message, correlationId: correlationId)
    }
}
