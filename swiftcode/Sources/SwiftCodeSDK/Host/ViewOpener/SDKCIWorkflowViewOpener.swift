import Foundation

public enum SDKCIWorkflowViewOpener {
    public static let viewID = "ci.VisualWF"

    public static func register() async {
        await SDKViewOpener.shared.register(viewID: viewID) {
            _ = try await SDKActiveProjectResolver.activeProjectRoot()
            try await SDKViewHostRegistry.shared.open(viewID: viewID)
        }
    }
}
