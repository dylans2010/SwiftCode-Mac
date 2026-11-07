import Foundation

public struct SDKCallerIdentity: Sendable {
    public let extensionID: String

    public let packageDigest: String

    public let projectRootPath: String

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

public enum SDKCapabilityBroker {

    public static func authorize(_ capability: SDKCapabilityID, for caller: SDKCallerIdentity) async throws {
        let correlationId = SDKError.newCorrelationId()

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

        guard let grant = await SDKGrantStore.shared.activeGrant(
            extensionID: caller.extensionID,
            capability: capability,
            projectRootPath: caller.projectRootPath
        ) else {
            try await denyForInactiveGrant(capability, caller: caller, correlationId: correlationId)
        }

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

    }

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
