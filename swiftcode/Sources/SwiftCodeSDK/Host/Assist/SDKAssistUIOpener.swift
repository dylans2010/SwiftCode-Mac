import Foundation

public enum SDKAssistUIOpener {
    public static let assistMainViewID = "assist.main"

    public static func registerAssistViewOpener() {
        Task { @MainActor in
            await SDKViewOpener.shared.register(viewID: assistMainViewID) {
                try await SDKViewHostRegistry.shared.openAssistMainView()
            }
        }
    }

    public static func openAssistView(caller: SDKCallerIdentity) async throws {
        guard let key = caller.apiKey else {
            await SDKAuditLog.shared.record(.assistDenied, extensionID: caller.extensionID, detail: "no key presented")
            throw SDKError(code: .assistDenied, message: SDKAssistGate.assistDeniedUserMessage)
        }
        try await SDKAssistService.shared.requireAssistEntitlement(key: key, extensionID: caller.extensionID)
        try await SDKViewOpener.shared.open(viewID: assistMainViewID)
    }
}
