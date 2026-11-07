import Foundation

public actor SDKIPCDispatcher {

    private static let requestTimeoutNanoseconds: UInt64 = 60 * 1_000_000_000

    private let session: SDKRuntimeSessionInfo
    private let send: @Sendable (Data) async -> Void
    private var buildHandles: [String: SDKBuildHandle] = [:]

    public init(session: SDKRuntimeSessionInfo, send: @Sendable @escaping (Data) async -> Void) {
        self.session = session
        self.send = send
    }

    public func dispatch(_ data: Data) async -> Data {
        var requestId = UUID().uuidString
        do {
            let header = try Self.peekHeader(from: data)
            if let peeked = header.requestId, !peeked.isEmpty {
                requestId = peeked
            }
            guard header.protocolVersion == SDKIPCCodec.sdkProtocolVersion else {
                throw SDKError(
                    code: .ipcProtocolMismatch,
                    message: "Unsupported IPC protocol version \(header.protocolVersion); this host speaks version \(SDKIPCCodec.sdkProtocolVersion).",
                    suggestion: "Update the extension's SDK to match the host protocol version."
                )
            }
            let messageType = try SDKIPCCodec.decodeEnvelopeType(from: data)
            guard messageType == .request else {
                throw SDKError(
                    code: .ipcMalformed,
                    message: "Expected a request envelope but received '\(messageType.rawValue)'.",
                    suggestion: "Send requests with \"type\": \"request\"."
                )
            }

            let envelope = try Self.decodeRequest(from: data)
            requestId = envelope.requestId
            let method = envelope.method

            try await SDKAssistGate.check(ipcMethod: method, callerExtensionID: session.extensionID)

            let captureRequestId = requestId
            return try await withPerRequestTimeout {
                let apiKey = try await self.verifySessionAPIKey()

                let caller = SDKCallerIdentity(
                    extensionID: self.session.extensionID,
                    packageDigest: self.session.packageDigest,
                    projectRootPath: self.session.projectRootPath,
                    apiKey: apiKey
                )

                return try await self.route(
                    method: method,
                    requestId: captureRequestId,
                    payload: envelope.payload,
                    caller: caller
                )
            }
        } catch let sdkError as SDKError {
            return Self.errorResponse(requestId: requestId, error: sdkError)
        } catch {
            return Self.errorResponse(requestId: requestId, error: SDKError(
                code: .serviceUnavailable,
                message: "The host could not complete the request.",
                suggestion: "Retry the request; quote the correlation ID if it persists.",
                diagnostics: ["underlyingError": error.localizedDescription]
            ))
        }
    }

    public func event(_ name: String, payload: SDKJSONValue, requestId: String) async {
        let envelope = SDKEventEnvelope<SDKJSONValue>(requestId: requestId, event: name, payload: payload)
        await send(SDKIPCCodec.encodeEvent(envelope))
    }

    private struct HeaderPeek: Decodable {
        let protocolVersion: Int
        let requestId: String?
    }

    private static func peekHeader(from data: Data) throws -> HeaderPeek {
        do {
            return try JSONDecoder().decode(HeaderPeek.self, from: data)
        } catch {
            throw SDKError(
                code: .ipcMalformed,
                message: "Message is not a valid SDK IPC envelope.",
                suggestion: "Send a JSON object with protocolVersion, type, and requestId fields.",
                diagnostics: ["underlyingError": error.localizedDescription]
            )
        }
    }

    private static func decodeRequest(from data: Data) throws -> SDKRequestEnvelope<SDKJSONValue> {
        do {
            return try JSONDecoder().decode(SDKRequestEnvelope<SDKJSONValue>.self, from: data)
        } catch {
            throw SDKError(
                code: .ipcMalformed,
                message: "The request envelope is malformed.",
                suggestion: "Send a JSON object with protocolVersion, type, requestId, method, and payload fields.",
                diagnostics: ["underlyingError": error.localizedDescription]
            )
        }
    }

    private static func errorResponse(requestId: String, error: SDKError) -> Data {
        SDKIPCCodec.encodeResponse(
            SDKResponseEnvelope<SDKJSONValue>(requestId: requestId, error: SDKErrorPayload(from: error))
        )
    }

    private static func successResponse<Payload: Codable & Sendable>(
        requestId: String,
        payload: Payload
    ) -> Data {
        SDKIPCCodec.encodeResponse(SDKResponseEnvelope(requestId: requestId, payload: payload))
    }

    private func verifySessionAPIKey() async throws -> SDKAPIKey? {
        guard let presented = session.presentedAPIKey else { return nil }
        do {
            return try await SDKAPIKeyStore.shared.verify(secret: presented)
        } catch {
            let sdkError = error as? SDKError
            await SDKAuditLog.shared.record(
                type: .apiKeyAuthFailure,
                extensionID: session.extensionID,
                detail: "session API key verification failed (\(sdkError?.code.rawValue ?? "unknown"))",
                correlationId: sdkError?.correlationId
            )
            throw error
        }
    }

    private func route(
        method: String,
        requestId: String,
        payload: SDKJSONValue,
        caller: SDKCallerIdentity
    ) async throws -> Data {
        switch method {
        case "sourceControl.getStatus":
            let status = try await SDKSourceControlAdapter.shared.getStatus(caller: caller)
            return Self.successResponse(requestId: requestId, payload: status)

        case "sourceControl.getDiff":
            let options = try Self.diffOptions(from: payload, method: method)
            let diff = try await SDKSourceControlAdapter.shared.getDiff(caller: caller, options: options)
            return Self.successResponse(requestId: requestId, payload: diff)

        case "build.run":
            let request = try Self.decodePayload(SDKBuildRequest.self, from: payload, method: method)
            let handle = try await SDKBuildService.shared.run(request: request, caller: caller)
            buildHandles[handle.id] = handle
            Task.detached { [self] in
                await self.forwardBuildEvents(handle: handle, requestId: requestId)
            }
            return Self.successResponse(
                requestId: requestId,
                payload: SDKJSONValue.object(["handleId": .string(handle.id)])
            )

        case "build.wait":
            let handle = try buildHandle(for: payload, method: method)
            let result = try await handle.wait()
            return Self.successResponse(requestId: requestId, payload: result)

        case "cloudModel.complete":
            let request = try Self.decodePayload(
                SDKCloudModelCompletionRequest.self,
                from: payload,
                method: method
            )
            let response = try await SDKCloudModelAdapter.shared.complete(request: request, caller: caller)
            return Self.successResponse(
                requestId: requestId,
                payload: SDKJSONValue.object(["response": .string(response)])
            )

        case "assist.invoke":
            let key = caller.apiKey
            guard key?.entitlements.contains(.developerAIAssist) ?? false else {
                throw await SDKAssistGate.deny(
                    callerExtensionID: caller.extensionID,
                    route: "ipc:assist.invoke"
                )
            }
            return try await self.routeAssistInvoke(
                payload: payload,
                requestId: requestId,
                caller: caller
            )

        case "build.cancel":
            let handle = try buildHandle(for: payload, method: method)
            await handle.cancel()
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "terminalSandbox.run":
            let request = try Self.decodePayload(SDKSandboxRunRequest.self, from: payload, method: method)
            let result = try await SDKSandboxedTerminal.shared.run(request: request, caller: caller)
            return Self.successResponse(requestId: requestId, payload: result)

        case "security.addValue":
            let addRequest = try Self.decodePayload(SDKSecurityAddRequest.self, from: payload, method: method)
            let added = try await SDKSecurityService.shared.addValue(request: addRequest, caller: caller)
            return Self.successResponse(requestId: requestId, payload: added)

        case "security.hasValue":
            let hasRequest = try Self.decodePayload(SDKSecurityLookupRequest.self, from: payload, method: method)
            let hasValue = try await SDKSecurityService.shared.hasValue(request: hasRequest, caller: caller)
            return Self.successResponse(requestId: requestId, payload: hasValue)

        case "security.listValueIDs":
            let listRequest = try Self.decodePayload(SDKSecurityListRequest.self, from: payload, method: method)
            let values = try await SDKSecurityService.shared.listValueIDs(request: listRequest, caller: caller)
            return Self.successResponse(requestId: requestId, payload: values)

        case "security.deleteValue":
            let deleteRequest = try Self.decodePayload(SDKSecurityLookupRequest.self, from: payload, method: method)
            try await SDKSecurityService.shared.deleteValue(request: deleteRequest, caller: caller)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "security.useValue":
            let useRequest = try Self.decodePayload(SDKSecurityUseRequest.self, from: payload, method: method)
            let useResult = try await SDKSecurityService.shared.useValue(request: useRequest, caller: caller)
            return Self.successResponse(requestId: requestId, payload: useResult)

        case "commands.register":
            try await SDKCapabilityBroker.authorize(.uiContribute, for: caller)
            let definition = try Self.decodePayload(SDKCommandDefinition.self, from: payload, method: method)
            try await SDKCommandRegistry.shared.register(definition, extensionID: caller.extensionID)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "commands.unregister":
            let commandID = try Self.stringField("commandID", from: payload, method: method)
            await SDKCommandRegistry.shared.unregister(commandID: commandID, extensionID: caller.extensionID)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "ui.openView":
            let viewID = try Self.viewID(from: payload, method: method)
            if viewID == .assistMainView {
                try await SDKAssistUIOpener.openAssistView(caller: caller)
                return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)
            }
            try await SDKCapabilityBroker.authorize(viewID, for: caller)
            try await SDKViewOpener.shared.open(viewID: viewID)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "log.debug", "log.info":
            let fields = try Self.logFields(from: payload, method: method)
            SDKUserLogger.shared.logInfo(fields.message, correlationId: fields.correlationId)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "log.warn":
            let fields = try Self.logFields(from: payload, method: method)
            SDKUserLogger.shared.logWarning(fields.message, correlationId: fields.correlationId)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "log.error":
            let fields = try Self.logFields(from: payload, method: method)
            SDKUserLogger.shared.log(
                error: ExtensionLogMessage(fields.message),
                title: "Extension error",
                correlationId: fields.correlationId
            )
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        default:
            throw SDKError(
                code: .ipcMalformed,
                message: "Unknown method \"\(method)\".",
                suggestion: "Use one of the documented SDK methods (e.g. \"sourceControl.getStatus\")."
            )
        }
    }

    private static func decodePayload<T: Decodable>(
        _ type: T.Type,
        from value: SDKJSONValue,
        method: String
    ) throws -> T {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SDKError(
                code: .invalidArgument,
                message: "The payload for \"\(method)\" is malformed.",
                suggestion: "Check the method's payload schema and retry.",
                diagnostics: ["underlyingError": error.localizedDescription]
            )
        }
    }

    private static func diffOptions(from payload: SDKJSONValue, method: String) throws -> SDKDiffOptions {
        guard case .object(let fields) = payload else {
            throw SDKError(
                code: .invalidArgument,
                message: "The payload for \"\(method)\" must be a JSON object.",
                suggestion: "Send an object, optionally with an \"options\" field."
            )
        }
        guard let optionsValue = fields["options"] else {
            return SDKDiffOptions()
        }
        return try decodePayload(SDKDiffOptions.self, from: optionsValue, method: method)
    }

    private static func stringField(
        _ name: String,
        from payload: SDKJSONValue,
        method: String
    ) throws -> String {
        guard case .object(let fields) = payload,
              let raw = fields[name],
              case .string(let value) = raw,
              !value.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "The payload for \"\(method)\" must be an object with a non-empty string \"\(name)\" field.",
                suggestion: "Send an object like {\"\(name)\": \"...\"}."
            )
        }
        return value
    }

    private static func logFields(
        from payload: SDKJSONValue,
        method: String
    ) throws -> (message: String, correlationId: String?) {
        guard case .object(let fields) = payload,
              let rawMessage = fields["message"],
              case .string(let message) = rawMessage,
              !message.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "The payload for \"\(method)\" must be an object with a non-empty string \"message\" field.",
                suggestion: "Send {\"message\": \"...\", \"correlationId\": \"...\"}."
            )
        }
        let correlationId: String?
        if let raw = fields["correlationId"], case .string(let value) = raw, !value.isEmpty {
            correlationId = value
        } else {
            correlationId = nil
        }
        return (message, correlationId)
    }

    private static func viewID(from payload: SDKJSONValue, method: String) throws -> SDKCapabilityID {
        let raw = try Self.stringField("viewId", from: payload, method: method)
        guard let viewID = SDKCapabilityID(rawValue: raw) else {
            throw SDKError(
                code: .unknownCapability,
                message: "Unknown view \"\(raw)\".",
                suggestion: "Use a capability ID from the SDK capability registry (e.g. \"db.ExploreView\")."
            )
        }
        return viewID
    }

    private func buildHandle(for payload: SDKJSONValue, method: String) throws -> SDKBuildHandle {
        let handleID = try Self.stringField("handleId", from: payload, method: method)
        guard let handle = buildHandles[handleID] else {
            throw SDKError(
                code: .invalidArgument,
                message: "Unknown build handle.",
                suggestion: "Start a build with \"build.run\" and use the \"handleId\" from its response."
            )
        }
        return handle
    }

    private func routeAssistInvoke(
        payload: SDKJSONValue,
        requestId: String,
        caller: SDKCallerIdentity
    ) async throws -> Data {
        let method = "assist.invoke"
        guard case .object(let fields) = payload,
              let rawOp = fields["op"],
              case .string(let op) = rawOp,
              !op.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "The payload for \"\(method)\" must be an object with a non-empty string \"op\" field.",
                suggestion: "Send one of \"session.create\", \"session.list\", \"message.send\", \"message.stream\", \"tool.invoke\", \"session.close\"."
            )
        }
        switch op {
        case "session.create":
            let options = try Self.assistSessionOptions(from: fields, method: method)
            let session = try await SDKAssistService.shared.createSession(caller: caller, options: options)
            return Self.successResponse(
                requestId: requestId,
                payload: SDKJSONValue.object([
                    "sessionId": .string(session.id.uuidString),
                    "createdAt": .string(Self.iso8601(session.createdAt)),
                ])
            )

        case "session.list":
            let sessions = try await SDKAssistService.shared.listSessions(caller: caller)
            return Self.successResponse(
                requestId: requestId,
                payload: SDKJSONValue.object([
                    "sessions": .array(sessions.map { session in
                        SDKJSONValue.object([
                            "sessionId": .string(session.id.uuidString),
                            "createdAt": .string(Self.iso8601(session.createdAt)),
                        ])
                    }),
                ])
            )

        case "message.send":
            let sessionID = try Self.assistSessionID(from: fields, method: method)
            let message = try Self.assistMessage(from: fields, method: method)
            let response = try await SDKAssistService.shared.send(
                sessionID: sessionID,
                message: message,
                caller: caller
            )
            return Self.successResponse(
                requestId: requestId,
                payload: SDKJSONValue.object(["reply": .string(response.text)])
            )

        case "message.stream":
            let sessionID = try Self.assistSessionID(from: fields, method: method)
            let message = try Self.assistMessage(from: fields, method: method)
            let stream = try await SDKAssistService.shared.sendStreaming(
                sessionID: sessionID,
                message: message,
                caller: caller
            )
            let forwarding = AssistStreamForwarding(stream: stream, requestId: requestId)
            Task.detached { [self] in
                await self.forwardAssistStream(forwarding)
            }
            return Self.successResponse(
                requestId: requestId,
                payload: SDKJSONValue.object(["accepted": .bool(true)])
            )

        case "tool.invoke":
            let sessionID = try Self.assistSessionID(from: fields, method: method)
            let toolCall = try Self.assistToolCall(from: fields, method: method)
            let result = try await SDKAssistService.shared.executeTool(
                sessionID: sessionID,
                toolCall: toolCall,
                caller: caller
            )
            return Self.successResponse(
                requestId: requestId,
                payload: SDKJSONValue.object([
                    "tool": .string(result.toolName),
                    "result": .string(result.output),
                ])
            )

        case "session.close":
            let sessionID = try Self.assistSessionID(from: fields, method: method)
            try await SDKAssistService.shared.closeSession(id: sessionID, caller: caller)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        default:
            throw SDKError(
                code: .invalidArgument,
                message: "Unknown assist operation \"\(op)\".",
                suggestion: "Send one of \"session.create\", \"session.list\", \"message.send\", \"message.stream\", \"tool.invoke\", \"session.close\"."
            )
        }
    }

    private static func assistSessionOptions(
        from fields: [String: SDKJSONValue],
        method: String
    ) throws -> SDKAssistSessionOptions {
        SDKAssistSessionOptions(
            systemPrompt: try assistOptionalString("systemPrompt", from: fields, method: method),
            model: try assistOptionalString("model", from: fields, method: method)
        )
    }

    private static func assistOptionalString(
        _ name: String,
        from fields: [String: SDKJSONValue],
        method: String
    ) throws -> String? {
        guard let raw = fields[name] else { return nil }
        guard case .string(let value) = raw else {
            throw SDKError(
                code: .invalidArgument,
                message: "The \"\(name)\" field of \"\(method)\" must be a string.",
                suggestion: "Omit \"\(name)\" or send it as a string."
            )
        }
        return value.isEmpty ? nil : value
    }

    private static func assistSessionID(
        from fields: [String: SDKJSONValue],
        method: String
    ) throws -> UUID {
        guard let raw = fields["sessionId"],
              case .string(let value) = raw,
              !value.isEmpty,
              let id = UUID(uuidString: value) else {
            throw SDKError(
                code: .invalidArgument,
                message: "The payload for \"\(method)\" must include a valid \"sessionId\" UUID string.",
                suggestion: "Use the \"sessionId\" returned by \"session.create\"."
            )
        }
        return id
    }

    private static func assistMessage(
        from fields: [String: SDKJSONValue],
        method: String
    ) throws -> String {
        guard let raw = fields["message"],
              case .string(let value) = raw,
              !value.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "The payload for \"\(method)\" must include a non-empty string \"message\" field.",
                suggestion: "Send {\"op\": \"message.send\", \"sessionId\": \"...\", \"message\": \"...\"}."
            )
        }
        return value
    }

    private static func assistToolCall(
        from fields: [String: SDKJSONValue],
        method: String
    ) throws -> SDKAssistToolCall {
        guard let rawTool = fields["tool"],
              case .string(let tool) = rawTool,
              !tool.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "The payload for \"\(method)\" must include a non-empty string \"tool\" field.",
                suggestion: "Send {\"op\": \"tool.invoke\", \"sessionId\": \"...\", \"tool\": \"...\", \"arguments\": {...}}."
            )
        }
        var arguments: [String: String] = [:]
        if let rawArguments = fields["arguments"] {
            guard case .object(let argumentFields) = rawArguments else {
                throw SDKError(
                    code: .invalidArgument,
                    message: "The \"arguments\" field of \"\(method)\" must be an object of string values.",
                    suggestion: "Send arguments like {\"query\": \"...\"}."
                )
            }
            for (argumentName, argumentValue) in argumentFields {
                guard case .string(let argumentString) = argumentValue else {
                    throw SDKError(
                        code: .invalidArgument,
                        message: "Tool argument \"\(argumentName)\" must be a string.",
                        suggestion: "Send arguments like {\"query\": \"...\"}."
                    )
                }
                arguments[argumentName] = argumentString
            }
        }
        return SDKAssistToolCall(toolName: tool, arguments: arguments)
    }

    private static nonisolated(unsafe) let assistISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func iso8601(_ date: Date) -> String {
        assistISO8601Formatter.string(from: date)
    }

    private func forwardAssistStream(_ forwarding: AssistStreamForwarding) async {
        for await streamEvent in forwarding.stream {
            switch streamEvent {
            case .started:
                break
            case .delta(let text):
                await event(
                    "assist.stream",
                    payload: SDKJSONValue.object([
                        "delta": .string(text),
                        "done": .bool(false),
                    ]),
                    requestId: forwarding.requestId
                )
            case .completed:
                await event(
                    "assist.stream",
                    payload: SDKJSONValue.object(["done": .bool(true)]),
                    requestId: forwarding.requestId
                )
            case .failed(let streamError):
                await event(
                    "assist.stream",
                    payload: SDKJSONValue.object([
                        "error": .string(streamError.code.rawValue),
                        "message": .string(streamError.message),
                        "done": .bool(true),
                    ]),
                    requestId: forwarding.requestId
                )
            }
        }
    }

    private func forwardBuildEvents(handle: SDKBuildHandle, requestId: String) async {
        for await output in await handle.events() {
            await event("build.output", payload: SDKJSONValue.object([
                "kind": .string(output.kind.rawValue),
                "text": .string(output.text),
                "timestamp": .double(output.timestamp.timeIntervalSince1970),
            ]), requestId: requestId)
        }
        do {
            let result = try await handle.wait()
            let payload = (try? Self.jsonValue(from: result)) ?? .null
            await event("build.finished", payload: payload, requestId: requestId)
        } catch let sdkError as SDKError {
            await event("build.finished", payload: SDKJSONValue.object([
                "status": .string(SDKBuildStatus.failed.rawValue),
                "code": .string(sdkError.code.rawValue),
                "message": .string(sdkError.message),
                "correlationId": .string(sdkError.correlationId),
            ]), requestId: requestId)
        } catch {
            await event("build.finished", payload: SDKJSONValue.object([
                "status": .string(SDKBuildStatus.failed.rawValue),
                "message": .string("The build result could not be retrieved."),
            ]), requestId: requestId)
        }
        buildHandles.removeValue(forKey: handle.id)
    }

    private static func jsonValue(from encodable: some Encodable) throws -> SDKJSONValue {
        let data = try JSONEncoder().encode(encodable)
        return try JSONDecoder().decode(SDKJSONValue.self, from: data)
    }

    private func withPerRequestTimeout<T: Sendable>(
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let timedOut = TimeoutFlag()
        let operationTask: Task<T, Error> = Task.detached(operation: operation)
        let watchdog = Task.detached {
            do {
                try await Task.sleep(nanoseconds: Self.requestTimeoutNanoseconds)
            } catch {
                return
            }
            await timedOut.mark()
            operationTask.cancel()
        }
        defer { watchdog.cancel() }
        do {
            return try await operationTask.value
        } catch {
            if await timedOut.didTimeOut {
                throw SDKError(
                    code: .ipcTimeout,
                    message: "The request timed out after 60 seconds.",
                    suggestion: "Retry the request. A running build keeps going — poll \"build.wait\" again for its result."
                )
            }
            throw error
        }
    }
}

private final class AssistStreamForwarding: @unchecked Sendable {
    let stream: AsyncStream<SDKAssistStreamEvent>
    let requestId: String

    init(stream: AsyncStream<SDKAssistStreamEvent>, requestId: String) {
        self.stream = stream
        self.requestId = requestId
    }
}

private actor TimeoutFlag {
    private var flag = false
    func mark() { flag = true }
    var didTimeOut: Bool { flag }
}

private struct ExtensionLogMessage: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
