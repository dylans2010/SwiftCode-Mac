import Foundation

public enum SDKAssistUIOpener {

    public static let assistMainViewID = "assist.main"

    public static func registerAssistViewOpener() async {
        await SDKViewOpener.shared.register(viewID: .assistMainView) {
            NotificationCenter.default.post(
                name: NSNotification.Name("SelectSidebarItem"),
                object: nil,
                userInfo: ["item": MainSidebarItem.agent.rawValue]
            )
        }
    }

    public static func openAssistView(caller: SDKCallerIdentity) async throws {
        let key = caller.apiKey
        guard key?.entitlements.contains(.developerAIAssist) ?? false else {
            let error = SDKError(
                code: .assistDenied,
                message: SDKAssistGate.assistDeniedUserMessage,
                suggestion: "The app developer can apply for Assist access in SwiftCode Studio; only a verified entitlement on the developer's API key unlocks Assist.",
                diagnostics: [
                    "route": "ui:openAssistView",
                    "keyId": key?.id.uuidString ?? "none",
                ]
            )
            await SDKAuditLog.shared.record(
                type: .assistDenied,
                extensionID: caller.extensionID,
                detail: "assist-sdk:ui:openAssistView: entitlement com.SwiftCode.developer-AI-Assist absent",
                correlationId: error.correlationId
            )
            throw error
        }
        try await SDKViewOpener.shared.open(viewID: .assistMainView)
    }
}
