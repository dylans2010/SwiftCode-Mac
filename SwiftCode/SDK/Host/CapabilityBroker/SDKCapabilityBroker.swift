import Foundation

// MARK: - SDKCapabilityBroker
//
// THE SINGLE AUTHORIZATION CHOKE POINT FOR THE SWIFTCODE SDK.
//
// Every privileged host operation — project reads, workspace reads/writes,
// source-control operations, builds, task execution, network requests, UI
// contributions, credential use — MUST call
// `SDKCapabilityBroker.authorize(_:for:)` on every call, before touching the
// underlying service. There is exactly one public entry point on purpose:
// authorization decisions are made in exactly one place so they cannot drift
// out of sync across adapters.
//
// SECURITY CONTROLS vs. NON-CONTROLS:
// - UI hiding, manifest capability claims, and TypeScript type signatures are
//   NOT security controls. A malicious extension can send arbitrary IPC
//   messages; the host validates identity, grants, scope, and package
//   identity here, on the receiving side, on EVERY call (spec §8.4).
// - A valid manifest is a request, not an authorization token.
// - `assist.invoke` is deny-by-default and NEVER grantable in this release
//   (spec §9); it is checked first, before any grant-store lookup, so no
//   grant, scope, or identity state can ever satisfy it.
//
// ENFORCEMENT ORDER (real checks, no short-circuits):
//   1. `assist.invoke` -> always deny + `assistDenied` audit event.
//   1a. `use.SwiftCodeModel` with a verified developer API key -> the
//       key-bound `com.SwiftCode.developer-AI-Allows-Cloud` entitlement is
//       the ONLY authorization (Docs/Intro-to-SDK.md §12); the grant store
//       is not consulted. Absent -> typed `.cloudModelDenied` carrying
//       the (proposed) verbatim user message + `cloudModelDenied` audit.
//       Present -> return authorized here; the host quota gate is still
//       enforced downstream by `SDKCloudModelAdapter` on every call.
//       Keyless sessions skip this gate and keep the pre-Part-B grant path.
//   1b. API-key scope gate: when the caller is bound to a verified
//       developer API key (the session presented one), privileged
//       capabilities (`SDKCapabilityRegistry.isPrivileged`) additionally
//       require the key to carry the `capabilities:request` scope ->
//       deny + `apiKeyScopeFailure` audit event. Sessions without a key
//       skip this gate (user grants alone decide).
//   2. Active-grant lookup in `SDKGrantStore` -> nil classifies precisely:
//        no record at all      -> PERMISSION_DENIED  (+ permissionDenied audit)
//        newest record revoked -> PERMISSION_REVOKED (+ permissionRevoked audit)
//        newest record expired -> PERMISSION_EXPIRED  (+ permissionDenied audit)
//        active but otherwise scoped -> PERMISSION_DENIED ("outside the
//        approved project"; activeGrant filtered it out on project root)
//   3. Scope check: standardized grant project root vs. standardized caller
//      root -> mismatch is PERMISSION_DENIED ("outside the approved project").
//   4. Package-digest binding: grant.packageDigest != caller.packageDigest ->
//      PERMISSION_DENIED ("extension was updated; re-approval required").
//      Reinstalls or content changes never silently inherit grants (spec §8.7).
//   5. Success returns Void — authorization is a gate, not a token. Nothing
//      is returned that the extension could cache or replay; the caller must
//      re-authorize on every privileged request.
//
// HONEST LIMITATION (until runtime Phase 4): extension registration and
// active-state tracking (spec §8.4's "registered and currently active"
// check) arrive with the runtime lifecycle. Until then the broker trusts the
// `SDKCallerIdentity` passed by host-owned code paths only — every call site
// of `authorize` MUST be host code (service adapters, host API façade).
// Extension-supplied identity fields are never accepted at the IPC boundary;
// identity is bound to the host-created runtime session there.

// MARK: - SDKCallerIdentity

/// The identity an extension presents when the host asks for a privileged
/// operation. Constructed ONLY by host-owned code from host-known state
/// (installed package registry + host-created runtime session). Extension
/// messages must never supply this directly.
public struct SDKCallerIdentity: Sendable {
    /// The extension ID from its validated manifest (e.g.
    /// "com.example.repository-build-extension").
    public let extensionID: String

    /// SHA-256 hex of the installed package the caller is running. Binds
    /// grants to the exact package content the user approved; any content
    /// change forces re-approval (spec §8.7).
    public let packageDigest: String

    /// Filesystem path of the project root the caller claims to act within.
    /// Checked against the grant's approved scope after normalization.
    public let projectRootPath: String

    /// Verified developer API key bound to the caller's session, if the
    /// session presented one (`SDKRuntimeSessionInfo.presentedAPIKey`,
    /// verified per-request by `SDKIPCDispatcher`). Nil for sessions
    /// without a key — those authorize purely through user grants.
    public let apiKey: SDKAPIKey?

    public init(
        extensionID: String,
        packageDigest: String,
        projectRootPath: String,
        apiKey: SDKAPIKey? = nil
    ) {
        self.extensionID = extensionID
        self.packageDigest = packageDigest
        self.projectRootPath = projectRootPath
        self.apiKey = apiKey
    }
}

// MARK: - SDKCapabilityBroker

/// The single authorization gate for SDK host operations. Stateless; all
/// state lives in `SDKGrantStore` (grants) and `SDKAuditLog` (audits).
public enum SDKCapabilityBroker {

    /// Authorize a single privileged operation. Throws an `SDKError` on any
    /// denial; returns `Void` on success (a gate, not a token).
    ///
    /// - Parameters:
    ///   - capability: The capability the requested operation maps to.
    ///   - caller: Host-constructed identity of the requesting extension.
    public static func authorize(_ capability: SDKCapabilityID, for caller: SDKCallerIdentity) async throws {
        let correlationId = SDKError.newCorrelationId()

        // --- 1. Assist gate: deny-by-default, never grantable. Checked FIRST,
        // --- before the grant store, so no grant can ever satisfy it.
        if capability == .assistInvoke {
            await SDKAuditLog.shared.record(
                type: .assistDenied,
                extensionID: caller.extensionID,
                capability: capability,
                detail: "assist.invoke requested",
                correlationId: correlationId
            )
            throw SDKError(
                code: .assistDenied,
                message: SDKAssistGate.assistDeniedUserMessage,
                suggestion: "The app developer can apply for Assist access in SwiftCode Studio; only a verified entitlement on the developer's API key unlocks Assist.",
                correlationId: correlationId
            )
        }

        // --- 1a. Cloud-model entitlement gate (Docs/Intro-to-SDK.md §12).
        // --- When the caller presents a verified developer API key, the
        // --- key-bound `com.SwiftCode.developer-AI-Allows-Cloud`
        // --- entitlement is the ONLY authorization for
        // --- `use.SwiftCodeModel` — the grant store is not consulted, and a
        // --- manifest/package-name/client-code claim is ignored (this code
        // --- reads only `caller.apiKey?.entitlements`). Absent -> typed
        // --- `.cloudModelDenied` carrying the (proposed) verbatim user
        // --- message + audit. Present -> return authorized: the host quota
        // --- gate is still enforced downstream by `SDKCloudModelAdapter`
        // --- on every call. Keyless sessions keep the pre-Part-B grant
        // --- path below.
        if capability == .useSwiftCodeModel, let apiKey = caller.apiKey {
            guard apiKey.entitlements.contains(.developerAIAllowsCloud) else {
                let error = SDKError(
                    code: .cloudModelDenied,
                    message: SDKAssistGate.cloudModelDeniedUserMessage,
                    suggestion: "The app developer can apply for cloud-model access in SwiftCode Studio; only a verified entitlement on the developer's API key unlocks the SwiftCode Cloud Model.",
                    correlationId: correlationId
                )
                await SDKAuditLog.shared.record(
                    type: .cloudModelDenied,
                    extensionID: caller.extensionID,
                    capability: capability,
                    detail: "use.SwiftCodeModel requested: entitlement com.SwiftCode.developer-AI-Allows-Cloud absent on key \(apiKey.id.uuidString)",
                    correlationId: correlationId
                )
                throw error
            }
            return
        }

        // --- 1b. API-key scope gate (spec §8.2.1). A session that presents
        // --- a developer API key opts into key-based authorization:
        // --- privileged capabilities additionally require the
        // --- `capabilities:request` scope on the key. Fail closed — a key
        // --- without the scope can never unlock a privileged capability,
        // --- no matter what grants exist. Keyless sessions skip this gate.
        if let apiKey = caller.apiKey, SDKCapabilityRegistry.isPrivileged(capability) {
            do {
                try await SDKAPIKeyStore.shared.requireScope(.capabilitiesRequest, for: apiKey)
            } catch {
                await SDKAuditLog.shared.record(
                    type: .apiKeyScopeFailure,
                    extensionID: caller.extensionID,
                    capability: capability,
                    detail: "authorize(\(capability.rawValue)) denied: session API key "
                        + "\(apiKey.id.uuidString) lacks \"capabilities:request\"",
                    correlationId: correlationId
                )
                throw error
            }
        }

        // --- 2/3. Grant lookup. A nil active grant is classified precisely by
        // --- inspecting the newest record for this capability (revoked and
        // --- expired records are deliberately NOT returned by activeGrant).
        guard let grant = await SDKGrantStore.shared.activeGrant(
            extensionID: caller.extensionID,
            capability: capability,
            projectRootPath: caller.projectRootPath
        ) else {
            try await denyForInactiveGrant(capability, caller: caller, correlationId: correlationId)
        }

        // --- 4. Scope check. activeGrant matched on the raw stored string; the
        // --- broker re-checks on normalized paths so "/a/../b", trailing
        // --- slashes, and other unnormalized spellings cannot escape scope.
        let approvedRoot = URL(fileURLWithPath: grant.scope.projectRootPath).standardized.path
        let callerRoot = URL(fileURLWithPath: caller.projectRootPath).standardized.path
        guard approvedRoot == callerRoot else {
            await SDKAuditLog.shared.record(
                type: .permissionDenied,
                extensionID: caller.extensionID,
                capability: capability,
                detail: "authorize(\(capability.rawValue)) denied: outside the approved project",
                correlationId: correlationId
            )
            throw SDKError(
                code: .permissionDenied,
                message: "This operation is outside the approved project.",
                suggestion: "Only use this capability within the project the user approved.",
                correlationId: correlationId
            )
        }

        // --- 5. Package-digest binding. A changed digest means the package
        // --- content changed after approval; grants never transfer silently.
        guard grant.packageDigest == caller.packageDigest else {
            await SDKAuditLog.shared.record(
                type: .permissionDenied,
                extensionID: caller.extensionID,
                capability: capability,
                detail: "authorize(\(capability.rawValue)) denied: extension was updated; re-approval required",
                correlationId: correlationId
            )
            throw SDKError(
                code: .permissionDenied,
                message: "This extension was updated; its permissions require re-approval.",
                suggestion: "Ask the user to re-approve this capability in SwiftCode Studio.",
                correlationId: correlationId
            )
        }

        // Authorized. The gate returns nothing by design.
    }

    // MARK: - Precise denial classification

    /// Throws the exact denial for a missing/inactive grant. `activeGrant`
    /// returns nil for four distinct states; this helper distinguishes them
    /// by inspecting the newest stored record for the capability.
    ///
    /// Classification order (newest record wins):
    ///   revoked -> PERMISSION_REVOKED (+ permissionRevoked audit)
    ///   expired -> PERMISSION_EXPIRED (+ permissionDenied audit)
    ///   active but path-filtered -> PERMISSION_DENIED, scope message
    ///   no record at all -> PERMISSION_DENIED, missing-grant message
    private static func denyForInactiveGrant(
        _ capability: SDKCapabilityID,
        caller: SDKCallerIdentity,
        correlationId: String
    ) async throws -> Never {
        let records = await SDKGrantStore.shared.grants(for: caller.extensionID)
        let newest = records
            .filter { $0.capability == capability }
            .max { $0.grantedAt < $1.grantedAt }

        guard let record = newest else {
            await SDKAuditLog.shared.record(
                type: .permissionDenied,
                extensionID: caller.extensionID,
                capability: capability,
                detail: "authorize(\(capability.rawValue)) denied: no grant for this capability",
                correlationId: correlationId
            )
            throw SDKError(
                code: .permissionDenied,
                message: "This extension has not been granted the '\(capability.rawValue)' capability.",
                suggestion: "Ask the user to approve this capability in SwiftCode Studio before the extension uses it.",
                correlationId: correlationId
            )
        }

        if record.revokedAt != nil {
            await SDKAuditLog.shared.record(
                type: .permissionRevoked,
                extensionID: caller.extensionID,
                capability: capability,
                detail: "authorize(\(capability.rawValue)) denied: grant was revoked",
                correlationId: correlationId
            )
            throw SDKError(
                code: .permissionRevoked,
                message: "The '\(capability.rawValue)' permission was revoked.",
                suggestion: "Ask the user to re-approve this capability in SwiftCode Studio.",
                correlationId: correlationId
            )
        }

        if let expiresAt = record.expiresAt, expiresAt <= Date() {
            await SDKAuditLog.shared.record(
                type: .permissionDenied,
                extensionID: caller.extensionID,
                capability: capability,
                detail: "authorize(\(capability.rawValue)) denied: grant expired",
                correlationId: correlationId
            )
            throw SDKError(
                code: .permissionExpired,
                message: "The '\(capability.rawValue)' permission has expired.",
                suggestion: "Ask the user to re-approve this capability in SwiftCode Studio.",
                correlationId: correlationId
            )
        }

        // The newest record is live (granted, not revoked, not expired), so
        // the only reason activeGrant filtered it out is the project-root
        // filter: the grant is scoped to a different project.
        await SDKAuditLog.shared.record(
            type: .permissionDenied,
            extensionID: caller.extensionID,
            capability: capability,
            detail: "authorize(\(capability.rawValue)) denied: grant scoped to a different project",
            correlationId: correlationId
        )
        throw SDKError(
            code: .permissionDenied,
            message: "This operation is outside the approved project.",
            suggestion: "Only use this capability within the project the user approved.",
            correlationId: correlationId
        )
    }
}
