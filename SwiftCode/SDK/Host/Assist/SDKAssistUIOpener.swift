import Foundation

// MARK: - SDKAssistUIOpener
//
// THE host path for the `assistSDK.UI` variant (Docs/Intro-to-SDK.md
// §11 — the Assist SDK variant WITH UI).
//
// The extension never touches Assist internals and gets no custom Assist
// chrome: the host presents the app's REAL `AssistMainView` for the agreed
// viewId `"assist.main"`, through the shared `SDKViewOpener` registry.
//
// Why `"assist.main"`: the deterministic assist.viewId rule (the sibling TS
// agent follows the same rule) — `SDKViewOpenerBuiltIns.swift` registers
// no Assist view, so the viewId is `assist.main`. `SDKCapabilityID`
// carries `.assistMainView = "assist.main"`, so both `ui.openView`'s
// `viewID(from:)` (rawValue mapping) and `SDKViewOpener.open(viewID:)`
// resolve the exact string.
//
// Why registration lives HERE and not in `SDKViewOpenerBuiltIns.swift`:
// the scopes-sync test (`scopes-sync.test.mjs`) enforces that every opener
// registered in BuiltIns has a matching `kind: "view"` entry in
// `ScopesIDLists.ts`/`ScopesIDLists.swift`, and the sibling's entries make
// `assist.ui` `kind: .api` (served over IPC, not as a view entry).
// Registering in BuiltIns would break that sync contract until sibling
// table entries land. The view-opener registry is explicitly open for
// extension (see `SDKViewOpener.swift` "Registering more openers"), so the
// Assist view registers from its own host module at SDK bootstrap —
// `SDKBootstrap.bootstrapIfNeeded()` calls `registerAssistViewOpener()`.
// Until that runs, `open` throws typed `.serviceUnavailable`: loud, never
// a silent no-op.
//
// The opener posts the app's REAL "show the Assist surface" notification:
// `AppCommands.swift:230` ("AI Agent" menu, ⇧⌘A) posts
// `NSNotification.Name("SelectSidebarItem")`, and `SidebarMainView`'s
// `.onReceive` resolves `userInfo["item"]` via `MainSidebarItem(rawValue:)`
// — the `.agent` case hosts the real `AssistMainView()`.
// NOTE the app-side quirk we deliberately do NOT copy: AppCommands posts
// the value `"agent"`, which matches NO `MainSidebarItem` rawValue (the
// `.agent` rawValue is its SF-symbol name), so the app's own menu item is
// a silent no-op today. We post `MainSidebarItem.agent.rawValue` —
// compile-checked, and the exact value the consumer resolves — so the
// real AssistMainView actually appears.
//
// Authorization: `openAssistView(caller:)` requires the key-bound
// `com.SwiftCode.developer-AI-Assist` entitlement FIRST (same boundary as
// `SDKAssistService`: only the verified API key record counts; manifest,
// package-name, and client-code claims are ignored). The registry itself
// performs no authorization by design — never call `SDKViewOpener.open`
// for this view from a path that bypasses this gate.

public enum SDKAssistUIOpener {

    /// The agreed viewId for the Assist main view (assist.viewId rule).
    /// The single Swift-side source of truth; the sibling TS surface uses
    /// the same literal.
    public static let assistMainViewID = "assist.main"

    /// Registers the Assist main-view opener with `SDKViewOpener`.
    /// Idempotent (last write wins); called once from `SDKBootstrap`.
    public static func registerAssistViewOpener() async {
        await SDKViewOpener.shared.register(viewID: .assistMainView) {
            NotificationCenter.default.post(
                name: NSNotification.Name("SelectSidebarItem"),
                object: nil,
                userInfo: ["item": MainSidebarItem.agent.rawValue]
            )
        }
    }

    /// Presents the host's real Assist main view for an entitled caller.
    ///
    /// Pipeline: entitlement (key-bound record only) → open the
    /// registered view. The extension never touches Assist internals.
    ///
    /// - Throws: typed `.assistDenied` carrying the verbatim §13 message
    ///   when the entitlement is absent (audited); `.serviceUnavailable`
    ///   when the opener is not registered (bootstrap has not run).
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
