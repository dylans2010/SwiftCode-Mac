import Foundation

// MARK: - SDKViewOpenerBuiltIns
//
// Ported from Legacy `SwiftCode/SDK/Host/ViewOpener/SDKViewOpenerBuiltIns.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Registers the 12 built-in view openers: 4 native-window surfaces,
// 5 toolbar surfaces, and 3 sibling openers (CI, virtualization, live
// preview — registered by their own files, called from here).
//
// Every opener delegates to the `SDKViewHost` seam (installed by
// YcodeUI). Legacy drove Legacy app window managers and the
// `com.swiftcode.toolbarToolActivated` notification bridge, neither of
// which exists in Ycode; the opener logic is ported, the windows are
// the host's job. An uninstalled host seam reports
// `.serviceUnavailable` naming the missing seam.

public enum SDKViewOpenerBuiltIns {
    /// All built-in view IDs, in registration order.
    public static let builtInViewIDs: [String] = [
        "db.ExploreView",
        "docs.search",
        "dictionary.open",
        "uibuilder.open",
        "deviceconnect.open",
        "simulator.view",
        "symbols.browse",
        "sandbox.view",
        "deployConsole.view",
        "ci.VisualWF",
        "virtualization.view",
        "preview.live",
    ]

    public static func registerBuiltInOpeners() {
        Task { @MainActor in
            let opener = SDKViewOpener.shared
            // Native-window surfaces (Legacy window managers).
            await opener.register(viewID: "db.ExploreView") {
                try await SDKViewHostRegistry.shared.open(viewID: "db.ExploreView")
            }
            await opener.register(viewID: "docs.search") {
                try await SDKViewHostRegistry.shared.open(viewID: "docs.search")
            }
            await opener.register(viewID: "dictionary.open") {
                try await SDKViewHostRegistry.shared.open(viewID: "dictionary.open")
            }
            await opener.register(viewID: "uibuilder.open") {
                try await SDKViewHostRegistry.shared.open(viewID: "uibuilder.open")
            }
            // Toolbar surfaces (Legacy notification bridges).
            await opener.register(viewID: "deviceconnect.open") {
                try await SDKViewHostRegistry.shared.open(viewID: "deviceconnect.open")
            }
            await opener.register(viewID: "simulator.view") {
                try await SDKViewHostRegistry.shared.open(viewID: "simulator.view")
            }
            await opener.register(viewID: "symbols.browse") {
                try await SDKViewHostRegistry.shared.open(viewID: "symbols.browse")
            }
            await opener.register(viewID: "sandbox.view") {
                try await SDKViewHostRegistry.shared.open(viewID: "sandbox.view")
            }
            await opener.register(viewID: "deployConsole.view") {
                try await SDKViewHostRegistry.shared.open(viewID: "deployConsole.view")
            }
            // Sibling openers (their own files).
            await SDKCIWorkflowViewOpener.register()
            await SDKVirtualizationViewOpener.register()
            await SDKLivePreviewViewOpener.register()
        }
    }
}
