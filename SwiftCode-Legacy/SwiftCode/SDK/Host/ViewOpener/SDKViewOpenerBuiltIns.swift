import Foundation

extension SDKViewOpener {

    private static let notificationBridges: [(viewID: SDKCapabilityID, toolID: String)] = [
        (.deviceConnectOpen, "deviceConnect"),
        (.simulatorView, "simulatorMain"),
        (.symbolsBrowse, "sfSymbolsBrowser"),
        (.sandboxView, "terminal"),
        (.deployConsoleView, "deployments"),
    ]

    public func registerBuiltInOpeners() async throws {
        register(viewID: .dbExploreView) {
            DatabaseExplorerWindowManager.shared.showWindow()
        }

        register(viewID: .docsSearch) {
            DocumentationBrowserWindowManager.shared.showWindow()
        }

        register(viewID: .dictionaryOpen) {
            CodingDictionaryWindowManager.shared.showWindow()
        }

        register(viewID: .uiBuilderOpen) {
            VisualUIBuilderWindowManager.shared.showWindow()
        }

        for bridge in Self.notificationBridges {
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
