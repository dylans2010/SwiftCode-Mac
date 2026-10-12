import Foundation

// MARK: - SDKAssistGate
//
// THE Assist deny-by-default gate for the SwiftCode SDK (Docs/Intro-to-SDK.md
// §9 — Restricted Assist authorization).
//
// Assist is explicitly OUT OF SCOPE for the first extension release. This
// type is the single place in the SDK surface where that refusal is
// enforced: it denies every attempt to reach Assist through an SDK surface,
// records it in the shared audit log, and returns a typed error. Callers
// THROW the returned `SDKError` — there is no success path here, and no
// dormant bypass (spec §9.2: "Do not implement a dormant bypass in the
// first release").
//
// ---------------------------------------------------------------------------
// What this gate enforces today (the REAL guarantee, this release):
//   (a) No SDK public API or IPC route exposes Assist without a key-bound
//       entitlement. The public `SwiftCodeContext` object does not include
//       `assist` (spec §9.1); the ONLY IPC route that can reach Assist is
//       the entitled `assist.invoke` route (Docs/Intro-to-SDK.md §13),
//       decided by the caller key's `com.SwiftCode.developer-AI-Assist`
//       entitlement at the dispatcher route AND re-checked on every
//       `SDKAssistService` call.
//   (b) `assist.invoke` (`SDKCapabilityID.assistInvoke`) is NEVER grantable.
//       The capability broker denies it first, independently of this gate.
//   (c) Every unentitled attempt that arrives through an SDK surface —
//       public API, IPC, or a manifest declaring `"assist": {"requested":
//       true}` — is denied with the verbatim §13 user message and audited
//       here, without exposing conversation content, model credentials, or
//       secret data. A manifest claim is descriptive metadata only; it is
//       never read as authorization.
//
// ---------------------------------------------------------------------------
// What this gate does NOT claim (be honest about the boundary):
//
// The host application's REAL Assist choke points are internal app
// machinery, not SDK types:
//   • `AssistManager.shared.sendMessage` — the primary send path.
//   • `AssistAPIRouter.route` — internal API routing.
//   • `LLMService.sendChatRequest` — the model call path.
//   • The Antigravity bridge Unix socket — the agentic-loop transport.
//
// None of those choke points currently identify an SDK extension as the
// caller, so none of them can gate per-extension Assist access on their own.
// Putting a gate there without caller identity would be theater. App-side
// caller-identity gating — plumbing the calling extension's identity from
// the SDK surface into `AssistManager`, the router, `LLMService`, and the
// bridge — is FUTURE WORK (spec §9.2) and must be designed and reviewed as
// its own feature.
//
// Until that exists, the enforceable guarantee is exactly (a)–(c) above:
// the SDK exposes no Assist surface to deny through, the broker denies the
// capability, and any attempt at the SDK layer is denied and audited HERE.
// Do not read a stronger claim into this file.
//
// ---------------------------------------------------------------------------
// Authorization is never inferred from manifest claims:
//
// `SDKManifestAssist.requested` is DESCRIPTIVE METADATA ONLY (spec §9.1,
// ADR §9). `manifestRequestsAssist(_:)` reads it so the host can report on
// it; it never grants anything. Likewise, authorization is never inferred
// from a logged-in user, an available model key, developer mode, an
// extension signature, or a previous grant for another capability
// (spec §9.1). Keep Assist authorization distinct from ordinary capability
// approval.

public enum SDKAssistGate {
    // MARK: - User-facing denial messages (single source of truth)
    //
    // Every Swift-side Assist denial — IPC gate, dispatcher route,
    // `SDKAssistService`, `SDKAssistUIOpener`, capability broker — must
    // emit EXACTLY these strings (Docs/Intro-to-SDK.md §13). They are
    // defined once, here, and referenced everywhere else; do not copy the
    // literals.

    /// The §13 Assist denial. VERBATIM — do not reword.
    public static let assistDeniedUserMessage =
        "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information."

    /// The cloud-model denial. PROPOSED wording — Dylan finalizes the
    /// exact text. Until he does, this is the string every Swift-side
    /// cloud denial emits, so the change is a one-line edit here.
    public static let cloudModelDeniedUserMessage =
        "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information."

    // MARK: - Deny-listed IPC method patterns
    //
    // Method-name patterns that must never reach Assist. Matching is
    // case-insensitive substring matching on the full method string (e.g.
    // `"assist.sendMessage"`, `"llm.sendChatRequest"`, `"AgentRunner.run"`).

    private static let deniedIPCPatterns: [String] = [
        "assist",
        "llm.",
        "agent_runner",
        "chat",
        "sendMessage",
    ]

    // MARK: - Entitled IPC methods
    //
    // Method names that PASS the deny-list above and are decided by
    // key-bound entitlement instead (Docs/Intro-to-SDK.md §13–§14, Part B).
    //
    // This set is intentionally minimal — exactly the wire method the
    // TypeScript `assistSDK` variant uses (`assist.invoke`, see
    // `TypeScript/package/src/assist.ts`). The exemption is SAFE because
    // the method can only reach the entitled route:
    // `SDKIPCDispatcher.route` checks the caller key's
    // `com.SwiftCode.developer-AI-Assist` entitlement BEFORE any op is
    // dispatched, and `SDKAssistService` re-checks the entitlement on
    // every call. An unentitled caller hitting `assist.invoke` gets the
    // typed `.assistDenied` with the verbatim message — never passthrough.
    // Every other method containing a denied substring is still denied
    // here, exactly as before.

    private static let entitledAssistMethods: Set<String> = [
        "assist.invoke",
    ]

    // MARK: - deny

    /// Denies an Assist attempt from `callerExtensionID` via the named route,
    /// audits it, and returns the error the caller must throw.
    ///
    /// - Parameters:
    ///   - callerExtensionID: The validated SDK extension ID making the
    ///     attempt (never a display name; never user content).
    ///   - route: Which SDK surface the attempt came through — one of
    ///     `"public-api"`, `"ipc"`, or `"manifest-request"` (detail may append
    ///     the concrete method, never payload content).
    /// - Returns: An `SDKError` with code `.assistDenied`. Callers THROW it.
    ///
    /// The audit record carries the error's correlation ID so a denied
    /// attempt can be traced end-to-end in the developer log. No conversation
    /// content, credentials, or secrets are ever recorded.
    public static func deny(callerExtensionID: String, route: String) async -> SDKError {
        let error = SDKError(
            code: .assistDenied,
            message: Self.assistDeniedUserMessage,
            suggestion: "The app developer can apply for Assist access in SwiftCode Studio; only a verified entitlement on the developer's API key unlocks Assist."
        )
        await SDKAuditLog.shared.record(
            type: .assistDenied,
            extensionID: callerExtensionID,
            capability: .assistInvoke,
            detail: route,
            correlationId: error.correlationId
        )
        return error
    }

    // MARK: - manifestRequestsAssist

    /// Reads the manifest's Assist flag as DESCRIPTIVE METADATA ONLY
    /// (spec §9.1, ADR §9).
    ///
    /// `requested: true` does NOT grant Assist access — the broker denies
    /// `assist.invoke` independently and `deny` denies the attempt. The
    /// return value tells the host what the extension *declared*, for
    /// reporting, so the host can explain a refusal with the right context.
    ///
    /// - Parameter manifest: A validated `SDKManifest`.
    /// - Returns: `manifest.assist.requested`.
    public static func manifestRequestsAssist(_ manifest: SDKManifest) -> Bool {
        manifest.assist.requested
    }

    // MARK: - check

    /// Inspects an incoming IPC method name and denies it when it targets
    /// Assist. Must be called by the SDK IPC dispatch path BEFORE any other
    /// routing or payload decoding for the method.
    ///
    /// Matching is case-insensitive substring matching against the
    /// deny-list (`"assist"`, `"llm."`, `"agent_runner"`, `"chat"`,
    /// `"sendMessage"`). A match records an `assistDenied` audit (route
    /// `"ipc"`, with the method name in the detail) and throws the deny
    /// error. A non-match returns normally — this method does not authorize
    /// anything, it only blocks what it recognizes.
    ///
    /// EXEMPTION: the exact method `"assist.invoke"` (case-insensitive) is
    /// the entitled Part-B route and passes through here — the caller-key
    /// entitlement check in `SDKIPCDispatcher.route` (plus the per-call
    /// re-check in `SDKAssistService`) decides it, denying unentitled
    /// callers with the verbatim §13 message. Nothing else containing a
    /// denied substring passes.
    ///
    /// - Parameters:
    ///   - ipcMethod: The full IPC method string, e.g. `"assist.sendMessage"`.
    ///   - callerExtensionID: The validated SDK extension ID issuing the call.
    /// - Throws: `SDKError` with code `.assistDenied` on any pattern match.
    public static func check(ipcMethod: String, callerExtensionID: String) async throws {
        let lowered = ipcMethod.lowercased()
        guard !entitledAssistMethods.contains(lowered) else { return }
        for pattern in deniedIPCPatterns where lowered.contains(pattern) {
            let error = SDKError(
                code: .assistDenied,
                message: Self.assistDeniedUserMessage,
                suggestion: "The app developer can apply for Assist access in SwiftCode Studio; only a verified entitlement on the developer's API key unlocks Assist."
            )
            await SDKAuditLog.shared.record(
                type: .assistDenied,
                extensionID: callerExtensionID,
                capability: .assistInvoke,
                detail: "ipc:\(ipcMethod)",
                correlationId: error.correlationId
            )
            throw error
        }
    }
}
