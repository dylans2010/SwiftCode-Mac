import Foundation

// MARK: - SDKViewOpener built-in openers
//
// The default viewID → open-action registrations, installed by
// `registerBuiltInOpeners()` (called once at host startup — see
// SDKViewOpener.swift "Bootstrap").
//
// Every entry point below was verified against app source on
// `feature/swiftcode-sdk` (2026-10-12); the per-area audits live in
// `/tmp/sdk-audit-*.md`. No view, window manager, notification name, or
// toolID here is invented — re-verify against source before changing one.
//
// Two opener styles:
//
// 1. Native-window views: call the app's REAL singleton window manager
//    directly (`*.shared.showWindow()`). These managers are `@MainActor`
//    classes with idempotent `showWindow()` — re-opening raises the
//    existing window.
// 2. Sheet views (Device Connect, Simulator workspace, SF Symbol picker):
//    there is NO public programmatic entry point — the app opens them only
//    through `WorkspaceView`'s `.sheet(item:)`, driven by the
//    `.toolbarToolActivated` notification (`Notification.Name` extension in
//    SwiftCode/Models/ToolbarItem.swift, raw name
//    "com.swiftcode.toolbarToolActivated"). The bridge posts the EXACT
//    `userInfo["toolID"]` strings the app's own `MainToolsView` posts for
//    those surfaces (MainToolsView.swift posts `tool.destination`), which
//    `ToolbarActionManager.destination(for:)` resolves — rawValue-first —
//    to the sheet destination `WorkspaceView` presents. Reuse, don't invent.
//
// The sibling openers (SDKCIWorkflowViewOpener, SDKVirtualizationViewOpener,
// SDKLivePreviewViewOpener — same directory) are wired here too, so one
// bootstrap call makes all ten view capabilities live.

extension SDKViewOpener {

    /// The sheet views opened through the app's own toolbar notification.
    /// `toolID` values are the exact destination strings `MainToolsView`
    /// posts for these surfaces; `ToolbarActionManager.destination(for:)`
    /// resolves each to the sheet `WorkspaceView` presents.
    private static let notificationBridges: [(viewID: SDKCapabilityID, toolID: String)] = [
        // Device Connect sheet. MainToolsView id "device_connect" posts
        // destination "deviceConnect"; BuildToolbarView posts "deviceConnect"
        // directly (BuildToolbarView.swift:69). destination(for:) also maps
        // "device_connect" / "device_connect_kit" → .deviceConnect.
        (.deviceConnectOpen, "deviceConnect"),
        // Simulator workspace sheet. MainToolsView id "simulator_main" posts
        // destination "simulatorMain" → .simulatorMain.
        (.simulatorView, "simulatorMain"),
        // SF Symbol picker sheet. MainToolsView id "sf_symbols" posts
        // destination "sfSymbolsBrowser" → .sfSymbolsBrowser.
        (.symbolsBrowse, "sfSymbolsBrowser"),
        // Terminal sheet. ToolbarActionManager "terminal" → .terminal, whose
        // WorkspaceView sheet hosts the REAL TerminalView (full interactive
        // shell — local shells, SSH nodes, themes). HIGH-RISK: this is not a
        // sandbox; opening it gives the user a complete unsandboxed shell.
        (.sandboxView, "terminal"),
        // Deployments console sheet. ToolbarActionManager "deployments" →
        // .deployments, whose WorkspaceView sheet hosts the REAL
        // DeploymentsView (Netlify / Vercel / GitHub Pages production
        // deployments). HIGH-RISK: deployments change production.
        (.deployConsoleView, "deployments"),
    ]

    /// Registers the twelve built-in view openers: four native-window managers,
    /// five toolbar-notification bridges, and the three sibling openers
    /// (CI workflows, virtualization console, live preview).
    ///
    /// - Throws: `.serviceUnavailable` if any bridge `toolID` no longer
    ///   resolves in `ToolbarActionManager.destination(for:)` — the app's
    ///   sheet routing changed, and posting a notification nobody can act
    ///   on would be a silent no-op. Failing fast at bootstrap keeps the
    ///   failure typed and loud.
    public func registerBuiltInOpeners() async throws {
        // --- 1. Native AppKit windows: the app's real window managers. ---
        // Database Explorer — DatabaseExplorerWindowManager
        // (SwiftCode/Views/Utilities/Database/DatabaseExplorerWindowManager.swift):
        // @MainActor, public shared, public showWindow(); the same call the
        // app's "Database Explorer" menu command makes (AppCommands.swift).
        register(viewID: .dbExploreView) {
            DatabaseExplorerWindowManager.shared.showWindow()
        }

        // Documentation browser — DocumentationBrowserWindowManager
        // (SwiftCode/Features/AdvancedTools/Views/DocumentationBrowserView.swift):
        // @MainActor, public shared, public showWindow().
        register(viewID: .docsSearch) {
            DocumentationBrowserWindowManager.shared.showWindow()
        }

        // Coding dictionary — CodingDictionaryWindowManager
        // (SwiftCode/Views/Utilities/CodingDictionaryView.swift):
        // @MainActor, public shared, public showWindow().
        register(viewID: .dictionaryOpen) {
            CodingDictionaryWindowManager.shared.showWindow()
        }

        // Visual UI Builder — VisualUIBuilderWindowManager
        // (SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIBuilderWindowManager.swift):
        // @MainActor, public shared, public showWindow(); the same call the
        // app's "Visual UI Builder" menu command makes (AppCommands.swift:83).
        register(viewID: .uiBuilderOpen) {
            VisualUIBuilderWindowManager.shared.showWindow()
        }

        // --- 2. Sheet views: the app's own toolbar-notification path. ---
        for bridge in Self.notificationBridges {
            // Guard the bridge BEFORE registering: if the app's toolbar can
            // no longer resolve this toolID, the notification would vanish
            // unheard. destination(for:) is @MainActor; hop there to check.
            let resolves = await ToolbarActionManager.shared.destination(for: bridge.toolID) != nil
            guard resolves else {
                throw SDKError(
                    code: .serviceUnavailable,
                    message: "The host cannot open view \"\(bridge.viewID.rawValue)\": the app's toolbar no longer resolves tool \"\(bridge.toolID)\".",
                    suggestion: "The app's sheet routing changed; update the SDK's notification-bridge tool IDs.",
                    diagnostics: ["viewId": bridge.viewID.rawValue, "toolID": bridge.toolID]
                )
            }
            let toolID = bridge.toolID
            register(viewID: bridge.viewID) {
                NotificationCenter.default.post(
                    name: .toolbarToolActivated,
                    object: nil,
                    userInfo: ["toolID": toolID]
                )
            }
        }

        // --- 3. Sibling openers: CI workflows, virtualization, live preview. ---
        // Each struct carries its own capabilityID and throws its own typed
        // errors (e.g. .projectNotOpen); register them so the table is the
        // single wiring point.
        register(viewID: SDKCIWorkflowViewOpener.capabilityID) {
            try SDKCIWorkflowViewOpener.open()
        }
        register(viewID: SDKVirtualizationViewOpener.capabilityID) {
            try SDKVirtualizationViewOpener.open()
        }
        register(viewID: SDKLivePreviewViewOpener.capabilityID) {
            try SDKLivePreviewViewOpener.open()
        }
    }
}
