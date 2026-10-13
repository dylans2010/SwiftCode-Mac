import Foundation

// MARK: - SDKIPCDispatcher
//
// Host-side IPC request dispatcher for one extension runtime session
// (Docs/Intro-to-SDK.md §10.4).
//
// Owns the full request pipeline for a single session: frame validation,
// Assist deny-listing (§9), session-bound identity binding (§10.4), routing
// with a per-request timeout, and response encoding. One dispatcher serves
// exactly one `SDKRuntimeSessionInfo`; the transport layer creates a fresh
// dispatcher per session, so no cross-extension state ever mixes here.
//
// ---------------------------------------------------------------------------
// SECURITY MODEL — READ THIS BEFORE TOUCHING THIS FILE
// ---------------------------------------------------------------------------
// 1. Extension-supplied identity is NEVER trusted. No identity fields are
//    read from the payload anywhere in this dispatcher. The
//    `SDKCallerIdentity` handed to every service is built from the
//    host-created `SDKRuntimeSessionInfo` (spec §10.4: "bind identity to
//    the host-created runtime session and validate it at the IPC boundary").
//
// 2. Every privileged method re-authorizes at the capability broker THROUGH
//    THE ADAPTERS — `SDKSourceControlAdapter` and `SDKBuildService` call
//    `SDKCapabilityBroker.authorize(_:for:)` on every call, before touching
//    the underlying service (spec §8.4: enforce at every host call). The
//    adapters are the authorization choke point. The dispatcher deliberately
//    does NOT pre-authorize: a second gate here would be a second place for
//    the policy to drift out of sync. Defense in depth is achieved by the
//    adapters authorizing on every call, not by duplicating the check here.
//
//    Documented exceptions to "the adapters authorize":
//    - `commands.register`: `SDKCommandRegistry` is a plain store with no
//      broker check of its own, so the dispatcher authorizes `.uiContribute`
//      at the broker before touching it.
//    - `ui.openView`: `SDKViewOpener` is a plain registry with no broker
//      check of its own, so the dispatcher authorizes the *view's own*
//      capability ID (taken from the payload) at the broker before the
//      opener runs. Each view is gated by exactly the grant the extension's
//      manifest declared; a denial surfaces as the broker's typed
//      permission error. EXCEPTION: the Assist main view (`assist.main`)
//      is entitlement-only (never grantable), so it is carved out to
//      `SDKAssistUIOpener.openAssistView`, which checks the key-bound
//      `com.SwiftCode.developer-AI-Assist` entitlement and emits the
//      verbatim §13 denial when absent.
//    - `assist.invoke`: the Part-B entitled Assist route. The caller key's
//      `com.SwiftCode.developer-AI-Assist` entitlement is checked HERE,
//      before any op is dispatched, and `SDKAssistService` re-checks it on
//      every call. Unentitled callers get the typed `.assistDenied` with
//      the verbatim §13 message — never passthrough, never a crash.
//    - `build.wait` / `build.cancel`: these act on handles minted by an
//      authorized `build.run` in this same session. The handle map is never
//      exposed to the extension and handle IDs are unguessable UUIDs, so
//      possession of a live handle IS the authorization for that handle.
//    - `commands.unregister`: ownership is enforced by the registry itself
//      (a foreign extension ID is a silent no-op).
//    - `log.*`: the extension's own diagnostics channel (spec §16.1); not a
//      privileged host operation, so no capability is involved.
//
// 3. Assist is deny-by-default (§9). `SDKAssistGate.check` runs FIRST —
//    before any routing or payload decoding — so no method name, however
//    spelled, can reach Assist through this dispatcher. The SOLE exemption
//    is the exact method `assist.invoke` (Docs/Intro-to-SDK.md §13): the
//    entitled Part-B route, which is decided by the caller key's
//    `com.SwiftCode.developer-AI-Assist` entitlement in `route` and
//    re-checked on every `SDKAssistService` call. Unentitled callers
//    hitting `assist.invoke` get the typed `.assistDenied` with the
//    verbatim §13 message.
//
// 4. Session API keys (§8.2.1). When the host-created session carries a
//    presented developer API key (`SDKRuntimeSessionInfo.presentedAPIKey`,
//    bound from the `SWIFTCODE_API_KEY` environment variable by the host
//    coordinator), the dispatcher verifies it against `SDKAPIKeyStore` on
//    EVERY request, before building the caller identity. Verification
//    failure fails the whole request closed with a typed error
//    (`.apiKeyInvalid` / `.apiKeyRevoked` / `.apiKeyRateLimited` /
//    `.serviceUnavailable`) — a session that presents a key must present a
//    VALID key. The verified key metadata rides on `SDKCallerIdentity.apiKey`
//    so the capability broker can enforce the `capabilities:request` scope
//    on privileged capabilities. Sessions without a key are unaffected.
//    The secret itself is never logged, never persisted, and never appears
//    in any error or audit record — only the failure code is recorded.

public actor SDKIPCDispatcher {

    // MARK: - Configuration

    /// Per-request wall-clock budget (spec §10.4: bounded requests).
    /// Expiry surfaces as `.ipcTimeout`; see `withPerRequestTimeout`.
    private static let requestTimeoutNanoseconds: UInt64 = 60 * 1_000_000_000

    // MARK: - State

    /// The host-created session this dispatcher serves. All caller identity
    /// is derived from here — never from the payload.
    private let session: SDKRuntimeSessionInfo
    /// Host → extension frame sink. Frames are newline-free single lines;
    /// the transport adds the NDJSON newline.
    private let send: @Sendable (Data) async -> Void
    /// Live build handles minted by `build.run` for this session, keyed by
    /// handle ID. Entries are removed when the build reaches a terminal
    /// state (see `forwardBuildEvents`).
    private var buildHandles: [String: SDKBuildHandle] = [:]

    public init(session: SDKRuntimeSessionInfo, send: @Sendable @escaping (Data) async -> Void) {
        self.session = session
        self.send = send
    }

    // MARK: - Dispatch

    /// Dispatches one inbound IPC frame and returns the response frame.
    ///
    /// NEVER throws outward: every failure — malformed frame, protocol
    /// mismatch, Assist denial, authorization denial, unknown method,
    /// malformed payload, service error, request timeout — is projected onto
    /// the wire as an `ok: false` response envelope carrying a typed
    /// `SDKErrorPayload`.
    ///
    /// Pipeline:
    ///   1. Frame validation: peek `protocolVersion` (≠ 1 → `.ipcProtocolMismatch`),
    ///      then `SDKIPCCodec.decodeEnvelopeType` (must be `.request`, else
    ///      `.ipcMalformed`; also enforces the 1 MiB frame bound).
    ///   2. Decode `SDKRequestEnvelope<SDKJSONValue>`; extract method + requestId.
    ///      FIRST — before any routing or payload decoding — run the Assist
    ///      deny-list (`SDKAssistGate.check`, §9). The exact method
    ///      `assist.invoke` is exempted there: it is the entitled Part-B
    ///      route, decided by the caller-key entitlement in `route`.
    ///   3. Verify the session's presented developer API key, if any
    ///      (`verifySessionAPIKey`, §8.2.1) — fail closed on any failure —
    ///      build the caller identity from the SESSION (never the payload),
    ///      attaching the verified key metadata when present, and route —
    ///      all inside the 60 s per-request timeout (→ `.ipcTimeout`).
    ///   4. Encode the `SDKResponseEnvelope` (`ok`/payload or `ok: false` +
    ///      `SDKErrorPayload(from:)`).
    public func dispatch(_ data: Data) async -> Data {
        // Best-effort requestId for pre-decode failures: the frame may not
        // even be JSON, so fall back to a fresh ID for the error envelope.
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

            // --- 2. Decode the request envelope to learn the method.
            let envelope = try Self.decodeRequest(from: data)
            requestId = envelope.requestId
            let method = envelope.method

            // --- 3. Assist deny-list FIRST: before routing or payload
            // --- decoding (§9). No method name, however spelled, reaches
            // --- Assist through this dispatcher — except the exact method
            // --- `assist.invoke`, the entitled Part-B route, which is
            // --- decided by the caller-key entitlement in `route` and
            // --- re-checked on every `SDKAssistService` call.
            try await SDKAssistGate.check(ipcMethod: method, callerExtensionID: session.extensionID)

            // --- 3b + 4 + 5. Session API-key verification (§8.2.1),
            // --- caller-identity binding, and routing — all inside the 60 s
            // --- per-request timeout. Verification runs inside the budget
            // --- because it performs Keychain I/O: it must never hang a
            // --- request past the deadline.
            //
            // --- 3b. Verified on EVERY request: revocation and expiry take
            // --- effect immediately, and no "still valid" verdict is cached.
            // --- Fail closed: any verification failure fails the request.
            let captureRequestId = requestId
            return try await withPerRequestTimeout {
                let apiKey = try await self.verifySessionAPIKey()

                // --- 4. Session-bound caller identity. Extension-supplied
                // --- identity is never trusted: no identity fields are read
                // --- from the payload anywhere in this dispatcher (§10.4).
                // --- The verified key (when the session presents one) rides
                // --- along so the broker can enforce `capabilities:request`.
                let caller = SDKCallerIdentity(
                    extensionID: self.session.extensionID,
                    packageDigest: self.session.packageDigest,
                    projectRootPath: self.session.projectRootPath,
                    apiKey: apiKey
                )

                // --- 5. Route.
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
            // Non-SDKError: the adapters are contractually SDKError-only, so
            // this is pure defense in depth. Never leak internals, never throw.
            return Self.errorResponse(requestId: requestId, error: SDKError(
                code: .serviceUnavailable,
                message: "The host could not complete the request.",
                suggestion: "Retry the request; quote the correlation ID if it persists.",
                diagnostics: ["underlyingError": error.localizedDescription]
            ))
        }
    }

    /// Sends an unsolicited event frame to the extension (e.g. build output).
    public func event(_ name: String, payload: SDKJSONValue, requestId: String) async {
        let envelope = SDKEventEnvelope<SDKJSONValue>(requestId: requestId, event: name, payload: payload)
        await send(SDKIPCCodec.encodeEvent(envelope))
    }

    // MARK: - Frame validation

    /// Minimal frame header: protocol version plus a best-effort request ID
    /// for error correlation before the full envelope is decoded.
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

    // MARK: - Session API-key verification

    /// Verifies the session's presented developer API key against
    /// `SDKAPIKeyStore` (spec §8.2.1), returning the verified metadata.
    ///
    /// - Returns: nil when the session presents no key (keyless sessions
    ///   authorize purely through user grants — today's behavior).
    /// - Throws: fails closed on every failure mode — `.apiKeyInvalid`
    ///   (malformed/forged/unknown/expired), `.apiKeyRevoked`,
    ///   `.apiKeyRateLimited`, `.serviceUnavailable`. The caller
    ///   (`dispatch`) projects the typed error onto the wire; a session
    ///   that presents a key must present a VALID key or nothing works.
    ///
    /// Called on EVERY request: revocation and expiry take effect on the
    /// next request, and no validity verdict is ever cached (see
    /// `SDKAPIKeyStore.verify`). The secret itself never appears in the
    /// audit record — only the extension/session IDs and the failure code.
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

    // MARK: - Routing
    //
    // Every privileged method re-authorizes at the broker THROUGH THE
    // ADAPTERS (see the file header): the dispatcher does not pre-authorize,
    // except on `commands.register` and `ui.openView`, where the registry
    // has no broker check of its own (the dispatcher authorizes
    // `.uiContribute` and the view's own capability ID respectively), and
    // on `assist.invoke`, where the dispatcher checks the caller key's
    // `com.SwiftCode.developer-AI-Assist` entitlement before dispatching
    // any op (the service re-checks per call). A malformed payload for a
    // KNOWN method is `.invalidArgument`;
    // an unknown method is `.ipcMalformed`.

    private func route(
        method: String,
        requestId: String,
        payload: SDKJSONValue,
        caller: SDKCallerIdentity
    ) async throws -> Data {
        switch method {
        case "sourceControl.getStatus":
            // The adapter authorizes `.sourceControlRead` at the broker.
            let status = try await SDKSourceControlAdapter.shared.getStatus(caller: caller)
            return Self.successResponse(requestId: requestId, payload: status)

        case "sourceControl.getDiff":
            // The adapter authorizes `.sourceControlRead` at the broker.
            let options = try Self.diffOptions(from: payload, method: method)
            let diff = try await SDKSourceControlAdapter.shared.getDiff(caller: caller, options: options)
            return Self.successResponse(requestId: requestId, payload: diff)

        case "build.run":
            // SDKBuildService.run authorizes `.buildExecute` at the broker.
            let request = try Self.decodePayload(SDKBuildRequest.self, from: payload, method: method)
            let handle = try await SDKBuildService.shared.run(request: request, caller: caller)
            buildHandles[handle.id] = handle
            // Detached: event forwarding must survive the request task (a
            // timed-out `build.wait` must not kill delivery) and must not
            // park this actor's executor on the output stream.
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
            // SDKCloudModelAdapter.complete authorizes `.useSwiftCodeModel`
            // at the broker on every call, enforces the host's quota gate,
            // and maps host cloud errors onto the SDK taxonomy. The endpoint
            // URL and device fingerprint never cross this boundary.
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
            // The Part-B entitled Assist route (Docs/Intro-to-SDK.md §13 —
            // the wire method the TypeScript `assistSDK` variant uses; see
            // `TypeScript/package/src/assist.ts`).
            //
            // EXACT ORDER OF CHECKS for this route:
            //   1. `SDKAssistGate.check` already ran in `dispatch` (step 3),
            //      before routing or payload decoding. The exact method
            //      `assist.invoke` is exempted from the deny-list there;
            //      every other `assist`-containing method was already denied.
            //   2. The session's presented API key was verified per-request
            //      in `dispatch` (step 3b) — revocation/expiry take effect
            //      immediately; a forged or invalid key fails the whole
            //      request closed before this route is reached.
            //   3. HERE: the caller key's `com.SwiftCode.developer-AI-Assist`
            //      entitlement is required. Manifest claims, package names,
            //      and client-code claims are ignored — only
            //      `caller.apiKey?.entitlements` is read. Absent -> the
            //      unified denial: typed `.assistDenied` with the verbatim
            //      §13 message + audit (no conversation content, no
            //      credentials; the key ID rides in internal diagnostics
            //      only).
            //   4. The `op` discriminator is decoded and dispatched to
            //      `SDKAssistService`, which re-checks the entitlement on
            //      every call. Malformed ops / forged payload claims ->
            //      typed `.invalidArgument`: never a crash, never passthrough.
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
            // SDKSandboxedTerminal.run authorizes `.terminalSandbox` at the
            // broker on every call, before any validation or process work.
            // This is host-mediated sandboxed execution, not a terminal
            // view: no shell, allow-listed executables only, cwd confined
            // to the caller's project scope, sanitized environment, hard
            // timeout with SIGKILL escalation, byte-capped output.
            let request = try Self.decodePayload(SDKSandboxRunRequest.self, from: payload, method: method)
            let result = try await SDKSandboxedTerminal.shared.run(request: request, caller: caller)
            return Self.successResponse(requestId: requestId, payload: result)

        case "security.addValue":
            // SDKSecurityService.addValue authorizes only `.useSecurity`
            // (the umbrella grant) at the broker on every call, before any
            // Keychain touch — the terminalSandbox.run pattern. The granular
            // `security.*` IDs are method scopes, not separately grantable,
            // and are never checked at the broker.
            // The Keychain namespace's extension component is derived from
            // the session-bound caller identity, never from the payload;
            // the secret is entered by the user into the host's secure
            // prompt and never crosses IPC. Resolves with {valueID, created}
            // metadata only.
            let addRequest = try Self.decodePayload(SDKSecurityAddRequest.self, from: payload, method: method)
            let added = try await SDKSecurityService.shared.addValue(request: addRequest, caller: caller)
            return Self.successResponse(requestId: requestId, payload: added)

        case "security.hasValue":
            // SDKSecurityService.hasValue authorizes only `.useSecurity`
            // at the broker on every call, before any Keychain touch.
            // Existence only — the secret is never returned.
            let hasRequest = try Self.decodePayload(SDKSecurityLookupRequest.self, from: payload, method: method)
            let hasValue = try await SDKSecurityService.shared.hasValue(request: hasRequest, caller: caller)
            return Self.successResponse(requestId: requestId, payload: hasValue)

        case "security.listValueIDs":
            // SDKSecurityService.listValueIDs authorizes only `.useSecurity`
            // at the broker on every call, before any Keychain touch.
            // Names and metadata only.
            let listRequest = try Self.decodePayload(SDKSecurityListRequest.self, from: payload, method: method)
            let values = try await SDKSecurityService.shared.listValueIDs(request: listRequest, caller: caller)
            return Self.successResponse(requestId: requestId, payload: values)

        case "security.deleteValue":
            // SDKSecurityService.deleteValue authorizes only `.useSecurity`
            // at the broker on every call, before any Keychain touch.
            let deleteRequest = try Self.decodePayload(SDKSecurityLookupRequest.self, from: payload, method: method)
            try await SDKSecurityService.shared.deleteValue(request: deleteRequest, caller: caller)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "security.useValue":
            // SDKSecurityService.useValue authorizes only `.useSecurity`
            // at the broker on every call, before any Keychain touch.
            // The secret is read via KeychainSDK's host-only read, attached
            // as the Authorization header of a host-built HTTPS request,
            // and only {status, body} comes back — the secret never enters
            // the response.
            let useRequest = try Self.decodePayload(SDKSecurityUseRequest.self, from: payload, method: method)
            let useResult = try await SDKSecurityService.shared.useValue(request: useRequest, caller: caller)
            return Self.successResponse(requestId: requestId, payload: useResult)

        case "commands.register":
            // The registry is a plain store with no broker check of its own:
            // authorize here, at the dispatcher, before touching it.
            try await SDKCapabilityBroker.authorize(.uiContribute, for: caller)
            let definition = try Self.decodePayload(SDKCommandDefinition.self, from: payload, method: method)
            try await SDKCommandRegistry.shared.register(definition, extensionID: caller.extensionID)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "commands.unregister":
            // Ownership is enforced by the registry itself (a foreign
            // extension ID is a silent no-op); the session binding is the
            // only identity that matters here.
            let commandID = try Self.stringField("commandID", from: payload, method: method)
            await SDKCommandRegistry.shared.unregister(commandID: commandID, extensionID: caller.extensionID)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "ui.openView":
            // SDKViewOpener is a plain registry with no broker check of its
            // own: authorize here, at the dispatcher, before touching it —
            // the commands.register pattern. The capability is the view's
            // own ID from the payload, so each view is gated by exactly the
            // grant the extension's manifest declared; a denial throws the
            // broker's typed permission error.
            //
            // CARVE-OUT: the Assist main view (`assist.main`,
            // `SDKCapabilityID.assistMainView`) is entitlement-only — never
            // grantable — so it does NOT go through the grant store below.
            // It goes to `SDKAssistUIOpener.openAssistView`, which requires
            // the key-bound `com.SwiftCode.developer-AI-Assist` entitlement
            // and emits the verbatim §13 denial when absent. (Without this
            // carve-out even an entitled caller would be denied, because no
            // grant for this capability can exist.)
            let viewID = try Self.viewID(from: payload, method: method)
            if viewID == .assistMainView {
                try await SDKAssistUIOpener.openAssistView(caller: caller)
                return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)
            }
            try await SDKCapabilityBroker.authorize(viewID, for: caller)
            try await SDKViewOpener.shared.open(viewID: viewID)
            return Self.successResponse(requestId: requestId, payload: SDKJSONValue.null)

        case "log.debug", "log.info":
            // The user log has no debug level; debug is recorded as info.
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

    // MARK: - Payload decoding

    /// Decodes a typed contract from an `SDKJSONValue` via a JSON
    /// round-trip. Any mismatch is `.invalidArgument`: the method is known,
    /// the payload is not.
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

    /// Tolerant `getDiff` options: the payload must be an object, but
    /// `options` itself is optional — absent means defaults (leveraging
    /// `SDKDiffOptions`' own tolerant decoding). Malformed `options` is
    /// `.invalidArgument`.
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

    /// Required non-empty string field of an object payload.
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

    /// `{"message": String, "correlationId"?: String}` for the `log.*` routes.
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

    /// `{"viewId": "<capability-id>"}` for the `ui.openView` route. The raw
    /// string must name a capability in the fixed `SDKCapabilityID` registry;
    /// an unknown ID is `.unknownCapability` — the same code the host's
    /// strict manifest validator uses for undeclared capability IDs (P1b).
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

    /// Looks up a live build handle minted by `build.run` in this session.
    /// Unknown IDs are `.invalidArgument` — the handle map is never exposed,
    /// so there is nothing else an extension could guess.
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

    // MARK: - Assist invoke routing (Part B)
    //
    // Dispatches the `assist.invoke` op discriminator (the exact wire
    // contract of `TypeScript/package/src/assist.ts`) to
    // `SDKAssistService`. The entitlement was already checked by the
    // caller (`route`); the service re-checks it on every call.
    //
    // Wire contract (method `assist.invoke`, payload always an object):
    //   {"op":"session.create","systemPrompt?","model?"} -> {"sessionId","createdAt"}
    //   {"op":"session.list"} -> {"sessions":[{"sessionId","createdAt"}]}
    //   {"op":"message.send","sessionId","message"} -> {"reply"}
    //   {"op":"message.stream","sessionId","message"} -> {"accepted":true}
    //     + `assist.stream` host events ({"delta","done"} / {"error","done":true})
    //   {"op":"tool.invoke","sessionId","tool","arguments"} -> {"tool","result"}
    //   {"op":"session.close","sessionId"} -> null
    //
    // Every malformed shape is `.invalidArgument`: the method is known,
    // the payload is not. Never a crash, never passthrough.

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
            // The entitlement check inside `sendStreaming` throws BEFORE
            // the stream is created, so calling it here preserves the wire
            // contract: a denial rejects the request with the typed
            // `.assistDenied` (it cannot happen in practice — the route
            // already checked — but the ordering is load-bearing for the
            // contract). The returned stream is handed to the detached
            // forwarder below; chunks arrive as `assist.stream` host events
            // correlated by this requestId, and the request resolves
            // {"accepted":true} once the host accepts the stream.
            let stream = try await SDKAssistService.shared.sendStreaming(
                sessionID: sessionID,
                message: message,
                caller: caller
            )
            let forwarding = AssistStreamForwarding(stream: stream, requestId: requestId)
            // Detached: event forwarding must survive the request task and
            // must not park this actor's executor on the stream's lifetime
            // (the build.run precedent).
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

    /// Decodes the `session.create` options from the raw wire fields.
    /// Unknown extra fields are ignored (wire-tolerant); wrongly typed
    /// known fields are `.invalidArgument`.
    private static func assistSessionOptions(
        from fields: [String: SDKJSONValue],
        method: String
    ) throws -> SDKAssistSessionOptions {
        SDKAssistSessionOptions(
            systemPrompt: try assistOptionalString("systemPrompt", from: fields, method: method),
            model: try assistOptionalString("model", from: fields, method: method)
        )
    }

    /// Optional non-empty string wire field. Present-but-not-a-string is
    /// `.invalidArgument`; absent or empty is nil.
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

    /// Required valid-UUID `sessionId` wire field. Anything else is
    /// `.invalidArgument` — never a crash on a forged ID.
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

    /// Required non-empty string `message` wire field. The service
    /// re-validates and bounds it; this is the wire-shape check.
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

    /// Decodes the `tool.invoke` tool call. Tool arguments must be an
    /// object of string values (the service's `SDKAssistToolCall` shape);
    /// anything else is `.invalidArgument`.
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

    /// Forwards one `message.stream` response stream as `assist.stream`
    /// host events, then ends. Runs detached from the request task (see
    /// the `message.stream` case): the request resolves {"accepted":true}
    /// as soon as the host accepts the stream, and chunks follow as events
    /// correlated by the request's requestId.
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

    // MARK: - Build event forwarding

    /// Streams a build's output to the extension as `build.output` events,
    /// then sends a terminal `build.finished` event carrying the `wait()`
    /// result. Runs detached from the request task (see `build.run`) and
    /// removes the handle from the registry once the build reaches a
    /// terminal state, so finished builds can be neither waited on nor
    /// cancelled again.
    private func forwardBuildEvents(handle: SDKBuildHandle, requestId: String) async {
        for await output in await handle.events() {
            await event("build.output", payload: SDKJSONValue.object([
                "kind": .string(output.kind.rawValue),
                "text": .string(output.text),
                "timestamp": .double(output.timestamp.timeIntervalSince1970),
            ]), requestId: requestId)
        }
        // The stream only ends after the handle reached a terminal state,
        // so `wait()` returns the cached result immediately here.
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

    /// Projects any Encodable contract onto `SDKJSONValue` via a JSON round-trip.
    private static func jsonValue(from encodable: some Encodable) throws -> SDKJSONValue {
        let data = try JSONEncoder().encode(encodable)
        return try JSONDecoder().decode(SDKJSONValue.self, from: data)
    }

    // MARK: - Per-request timeout

    /// Runs `operation` with a 60 s wall-clock budget. On expiry the
    /// operation is cancelled and `.ipcTimeout` is thrown — promptly, without
    /// waiting for a non-cooperative operation (e.g. `build.wait` on a long
    /// build) to observe cancellation. The operation itself keeps running
    /// detached: a timed-out build keeps building, its handle stays
    /// registered, and the extension can poll `build.wait` again.
    ///
    /// This is intentionally NOT the task-group race used by
    /// `SDKSourceControlAdapter.withTimeout`: a group scope joins its
    /// children on exit, so a non-cooperative loser would delay the timeout
    /// error past the budget. The detached watchdog + exactly-once latch
    /// delivers the error at 60 s in all cases.
    private func withPerRequestTimeout<T: Sendable>(
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let timedOut = TimeoutFlag()
        let operationTask: Task<T, Error> = Task.detached(operation: operation)
        let watchdog = Task.detached {
            do {
                try await Task.sleep(nanoseconds: Self.requestTimeoutNanoseconds)
            } catch {
                return // Cancelled: the operation finished first.
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

// MARK: - AssistStreamForwarding

/// One `message.stream` forwarding job: carries the service's response
/// stream and the originating request ID across the handoff from the
/// request task to the detached forwarder
/// (`SDKIPCDispatcher.forwardAssistStream`).
///
/// `AsyncStream` is not `Sendable`, so the stream cannot be captured
/// directly by the `Task.detached` closure (whose operation is
/// `@Sendable`). This box carries it across exactly one handoff —
/// request task → detached forwarder — after which exactly one `for await`
/// loop consumes it and nothing else touches it. Single producer, single
/// consumer, no shared mutation: `@unchecked Sendable` is sound here.
/// `requestId` correlates the emitted `assist.stream` host events.
private final class AssistStreamForwarding: @unchecked Sendable {
    let stream: AsyncStream<SDKAssistStreamEvent>
    let requestId: String

    init(stream: AsyncStream<SDKAssistStreamEvent>, requestId: String) {
        self.stream = stream
        self.requestId = requestId
    }
}

// MARK: - TimeoutFlag

/// Exactly-once latch distinguishing "the watchdog fired" from any other
/// cancellation, so only a genuine timeout maps to `.ipcTimeout`.
private actor TimeoutFlag {
    private var flag = false
    func mark() { flag = true }
    var didTimeOut: Bool { flag }
}

// MARK: - ExtensionLogMessage

/// Wraps an extension-supplied log string as an `Error` so it can travel
/// through `SDKUserLogger.log(error:title:)` — which sanitizes before
/// buffering or emitting. The title marks it as extension-originated; never
/// confuse it with a host error.
private struct ExtensionLogMessage: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
