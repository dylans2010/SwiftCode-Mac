import Foundation

public enum SDKViewOpenerBuiltIns {
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
            await SDKCIWorkflowViewOpener.register()
            await SDKVirtualizationViewOpener.register()
            await SDKLivePreviewViewOpener.register()
        }
    }
}
