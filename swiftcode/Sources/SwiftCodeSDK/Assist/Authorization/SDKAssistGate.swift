import Foundation
import SwiftCodeExtensions

public enum SDKAssistGate {
    public static let assistDeniedUserMessage =
        "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information."

    public static let cloudModelDeniedUserMessage =
        "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information."

    public static let deniedIPCSubstrings: [String] = [
        "assist",
        "llm.",
        "agent_runner",
        "chat",
        "sendMessage",
    ]

    public static let entitledAssistMethods: Set<String> = ["assist.invoke"]

    public static func deny(callerExtensionID: String, route: String) async -> SDKError {
        await SDKAuditLog.shared.record(
            .assistDenied,
            extensionID: callerExtensionID,
            detail: "route \(route)"
        )
        return SDKError(code: .assistDenied, message: assistDeniedUserMessage)
    }

    public static func manifestRequestsAssist(_ capabilities: [SDKCapabilityID]) -> Bool {
        capabilities.contains { id in
            id == .assistInvoke || id == .assistUI || id == .assistHeadless || id == .assistMainView
        }
    }

    public static func check(ipcMethod: String, callerExtensionID: String) async throws {
        let lowered = ipcMethod.lowercased()
        if entitledAssistMethods.contains(lowered) { return }
        for fragment in deniedIPCSubstrings where lowered.contains(fragment) {
            throw await deny(callerExtensionID: callerExtensionID, route: ipcMethod)
        }
    }
}
