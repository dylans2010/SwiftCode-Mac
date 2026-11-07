import Foundation
import SwiftCodeExtensions

public struct SDKCallerIdentity: Sendable {
    public let extensionID: String
    public let packageDigest: String
    public let projectRootPath: String
    public let apiKey: SDKAPIKey?

    public init(extensionID: String, packageDigest: String, projectRootPath: String, apiKey: SDKAPIKey? = nil) {
        self.extensionID = extensionID
        self.packageDigest = packageDigest
        self.projectRootPath = projectRootPath
        self.apiKey = apiKey
    }
}

public enum SDKCapabilityBroker {
    public static let permissions = PermissionManager()

    public static func authorize(
        _ capability: SDKCapabilityID,
        for caller: SDKCallerIdentity,
        permissions: PermissionManager = SDKCapabilityBroker.permissions
    ) async throws {
        if capability == .assistInvoke {
            throw await SDKAssistGate.deny(callerExtensionID: caller.extensionID, route: "assist.invoke")
        }

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

        if let key = caller.apiKey, SDKCapabilityRegistry.isPrivileged(capability) {
            try await SDKAPIKeyStore.shared.requireScope(.capabilitiesRequest, on: key)
        }

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

        let scopeRoot = (caller.projectRootPath as NSString).standardizingPath
        guard !scopeRoot.isEmpty, scopeRoot != "/" else {
            throw SDKError(code: .projectOutOfScope, message: "The operation is outside the approved project.")
        }

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
