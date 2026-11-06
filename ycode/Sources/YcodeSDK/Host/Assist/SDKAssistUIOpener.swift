import Foundation

// MARK: - SDKAssistUIOpener
//
// Ported from Legacy `SwiftCode/SDK/Host/Assist/SDKAssistUIOpener.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Registers the `assist.main` view opener: the entitled route through
// which an extension opens the host's real Assist main view. The view
// itself is owned by the host UI (YcodeUI); this file only owns the
// entitlement check and the registration.

public enum SDKAssistUIOpener {
    /// The view ID the `assistSDK.UI` variant opens through `ui.openView`.
    public static let assistMainViewID = "assist.main"

    /// Registers the Assist view opener with the view-opener registry.
    /// Call once at SDK bootstrap, after the host UI has installed its
    /// `SDKViewHost` seam (see `SDKViewOpenerBuiltIns`).
    public static func registerAssistViewOpener() {
        Task { @MainActor in
            await SDKViewOpener.shared.register(viewID: assistMainViewID) {
                try await SDKViewHostRegistry.shared.openAssistMainView()
            }
        }
    }

    /// Opens the Assist main view for an entitled caller. Requires the
    /// `developerAIAssist` entitlement on the VERIFIED key record;
    /// otherwise `.assistDenied` with the verbatim message, audited.
    /// An unregistered view is `.serviceUnavailable` — the host UI seam
    /// is missing, and the failure is reported honestly.
    public static func openAssistView(caller: SDKCallerIdentity) async throws {
        guard let key = caller.apiKey else {
            await SDKAuditLog.shared.record(.assistDenied, extensionID: caller.extensionID, detail: "no key presented")
            throw SDKError(code: .assistDenied, message: SDKAssistGate.assistDeniedUserMessage)
        }
        try await SDKAssistService.shared.requireAssistEntitlement(key: key, extensionID: caller.extensionID)
        try await SDKViewOpener.shared.open(viewID: assistMainViewID)
    }
}
