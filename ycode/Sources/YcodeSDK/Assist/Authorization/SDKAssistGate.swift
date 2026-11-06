import Foundation
import YcodeExtensions

// MARK: - SDKAssistGate
//
// Ported from Legacy `SwiftCode/SDK/Assist/Authorization/SDKAssistGate.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The Assist gate is deny-by-default. Assist is unavailable to extensions
// in this release except through the key-bound entitlement flow: the
// broker denies `assist.invoke` unconditionally, and the IPC dispatcher
// consults this gate BEFORE routing or decoding any Assist message.
// The gate never fabricates access — when it denies, callers THROW the
// returned error.
//
// Honest boundary: the real Assist choke points (the host's Assist
// session loop, the LLM service) have no extension caller identity in
// this release, so this gate can only guard the SDK IPC surface. Wiring
// caller identity into the host Assist stack is future work, recorded in
// the slice spec draft.

public enum SDKAssistGate {
    /// Verbatim user message for an Assist denial. Do not reword.
    public static let assistDeniedUserMessage =
        "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information."

    /// PROPOSED user message for a cloud-model denial. Dylan finalizes
    /// the wording; do not ship a different message without his sign-off.
    public static let cloudModelDeniedUserMessage =
        "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information."

    /// IPC method-name fragments that are Assist-shaped. A deny-listed
    /// route is rejected before routing or decoding, case-insensitively.
    /// `assist.invoke` itself is exempt: it is the entitled route, and
    /// the dispatcher checks the entitlement there.
    public static let deniedIPCSubstrings: [String] = [
        "assist",
        "llm.",
        "agent_runner",
        "chat",
        "sendMessage",
    ]

    /// Methods the entitled `assist.invoke` route may carry. Everything
    /// else on that route is rejected.
    public static let entitledAssistMethods: Set<String> = ["assist.invoke"]

    /// Builds the denial error for `extensionID` on `route`, records the
    /// audit event, and returns it. Callers THROW the result.
    public static func deny(callerExtensionID: String, route: String) async -> SDKError {
        await SDKAuditLog.shared.record(
            .assistDenied,
            extensionID: callerExtensionID,
            detail: "route \(route)"
        )
        return SDKError(code: .assistDenied, message: assistDeniedUserMessage)
    }

    /// Descriptive only: whether a manifest's declared capabilities
    /// include any Assist-shaped capability. Used by Studio surfaces to
    /// explain why an extension cannot use Assist; it grants nothing.
    public static func manifestRequestsAssist(_ capabilities: [SDKCapabilityID]) -> Bool {
        capabilities.contains { id in
            id == .assistInvoke || id == .assistUI || id == .assistHeadless || id == .assistMainView
        }
    }

    /// Checks an IPC method name for an extension caller. Throws
    /// `.assistDenied` (audited) when the method is Assist-shaped and not
    /// the entitled `assist.invoke` route. Call this BEFORE routing or
    /// decoding the payload.
    public static func check(ipcMethod: String, callerExtensionID: String) async throws {
        if entitledAssistMethods.contains(ipcMethod) { return }
        let lowered = ipcMethod.lowercased()
        for fragment in deniedIPCSubstrings where lowered.contains(fragment) {
            throw await deny(callerExtensionID: callerExtensionID, route: ipcMethod)
        }
    }
}
