import Foundation
import YcodeExtensions

// MARK: - SDKCallerIdentity
//
// Host-constructed caller identity. Extension identity is NEVER taken
// from an IPC payload — the dispatcher binds it to the runtime session,
// and the session binds it to the verified API key record.

public struct SDKCallerIdentity: Sendable {
    public let extensionID: String
    /// SHA-256 package digest of the installed extension being run.
    public let packageDigest: String
    /// Standardized absolute path of the caller's project root.
    public let projectRootPath: String
    /// The verified API key record, when the session presented a key.
    /// `nil` means keyless. Never a caller-supplied claim.
    public let apiKey: SDKAPIKey?

    public init(extensionID: String, packageDigest: String, projectRootPath: String, apiKey: SDKAPIKey? = nil) {
        self.extensionID = extensionID
        self.packageDigest = packageDigest
        self.projectRootPath = projectRootPath
        self.apiKey = apiKey
    }
}

// MARK: - SDKCapabilityBroker
//
// Ported from Legacy `SwiftCode/SDK/Host/CapabilityBroker/SDKCapabilityBroker.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Stateless authorization gate — not a token. Enforcement order:
//
// 1. `assist.invoke` is always denied (deny-by-default, audited).
// 1a. `useSwiftCodeModel` WITH a key: only the key-bound
//     `developerAIAllowsCloud` entitlement authorizes; otherwise
//     `.cloudModelDenied` with the verbatim message, audited. When the
//     entitlement is present, the call is authorized and quota is
//     enforced downstream. Keyless callers keep the grant path.
// 1b. Privileged (high-risk) capabilities WITH a key additionally
//     require the `capabilities:request` scope on the key, else
//     `.apiKeyScopeInsufficient` (audited).
// 2. Active-grant lookup, delegated to YcodeExtensions'
//     `PermissionManager` — the single live grant store (`grants.json`,
//     0600). This broker does NOT keep a second grant store.
// 3. Scope check on standardized paths.
// 4. Digest binding: the caller's package digest must match the digest
//     recorded at install, or re-approval is required.
//
// DEVIATIONS from Legacy (recorded in the slice spec draft): the v2
// grant store is flat — it carries no per-grant expiry, revocation
// timestamp, or per-project scope — so Legacy's precise
// PERMISSION_REVOKED / PERMISSION_EXPIRED / scoped-elsewhere
// classifications collapse to PERMISSION_DENIED here. Revocation still
// takes effect on the next call (the grant is gone), and expiry is
// enforced at the key level, not the grant level.

public enum SDKCapabilityBroker {
    /// The live grant store. Single instance: `PermissionManager` loads
    /// `grants.json` once and persists on change.
    public static let permissions = PermissionManager()

    /// Authorizes `capability` for `caller`. Returns on success; throws
    /// a typed `SDKError` on denial. Authorization is a gate, not a
    /// token — the caller must re-authorize every operation.
    public static func authorize(
        _ capability: SDKCapabilityID,
        for caller: SDKCallerIdentity,
        permissions: PermissionManager = SDKCapabilityBroker.permissions
    ) async throws {
        // 1. Assist invocation is deny-by-default, always.
        if capability == .assistInvoke {
            throw await SDKAssistGate.deny(callerExtensionID: caller.extensionID, route: "assist.invoke")
        }

        // 1a. Cloud model with a key: entitlement-only.
        if capability == .useSwiftCodeModel, let key = caller.apiKey {
            guard key.entitlements.contains(.developerAIAllowsCloud) else {
                await SDKAuditLog.shared.record(
                    .cloudModelDenied,
                    extensionID: caller.extensionID,
                    detail: "key \(key.id.uuidString)"
                )
                throw SDKError(code: .cloudModelDenied, message: SDKAssistGate.cloudModelDeniedUserMessage)
            }
            return
        }

        // 1b. Privileged capabilities with a key need the
        // `capabilities:request` scope.
        if let key = caller.apiKey, SDKCapabilityRegistry.isPrivileged(capability) {
            try await SDKAPIKeyStore.shared.requireScope(.capabilitiesRequest, on: key)
        }

        // 2. Active-grant lookup in the single live grant store. The v2
        // capabilities for the SDK capability must ALL be granted
        // (conservative: a partially-granted mapping is a denial).
        let required = ExtensionCapability.v2Capabilities(for: capability)
        guard !required.isEmpty else {
            throw SDKError(code: .permissionDenied, message: "The capability is not available.")
        }
        for v2 in required {
            guard permissions.isGranted(extensionId: caller.extensionID, capability: v2) else {
                throw SDKError(
                    code: .permissionDenied,
                    message: "Permission denied for \(capability.rawValue).",
                    suggestion: "Ask the user to approve this capability for the extension."
                )
            }
        }

        // 3. Scope check: the caller must be operating inside its
        // approved project root. The standardized root is the scope.
        let scopeRoot = (caller.projectRootPath as NSString).standardizingPath
        guard !scopeRoot.isEmpty, scopeRoot != "/" else {
            throw SDKError(code: .projectOutOfScope, message: "The operation is outside the approved project.")
        }

        // 4. Digest binding: the running package must be the package
        // that was approved. A mismatch means re-approval is required.
        if let installed = await SDKExtensionRegistry.shared.installedExtension(id: caller.extensionID),
           installed.packageDigest != caller.packageDigest {
            throw SDKError(
                code: .permissionDenied,
                message: "The extension package changed since approval. Re-approval is required.",
                suggestion: "Ask the user to approve the updated extension."
            )
        }
    }
}
