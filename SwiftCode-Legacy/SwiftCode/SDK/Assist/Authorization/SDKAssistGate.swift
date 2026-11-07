import Foundation

public enum SDKAssistGate {

    public static let assistDeniedUserMessage =
        "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information."

    public static let cloudModelDeniedUserMessage =
        "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information."

    private static let deniedIPCPatterns: [String] = [
        "assist",
        "llm.",
        "agent_runner",
        "chat",
        "sendMessage",
    ]

    private static let entitledAssistMethods: Set<String> = [
        "assist.invoke",
    ]

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

    public static func manifestRequestsAssist(_ manifest: SDKManifest) -> Bool {
        manifest.assist.requested
    }

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
