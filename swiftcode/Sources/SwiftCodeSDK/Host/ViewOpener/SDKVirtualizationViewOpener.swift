import Foundation

public enum SDKVirtualizationViewOpener {
    public static let viewID = "virtualization.view"

    public static func register() async {
        await SDKViewOpener.shared.register(viewID: viewID) {
            _ = try await SDKActiveProjectResolver.activeProjectRoot()
            try await SDKViewHostRegistry.shared.open(viewID: viewID)
        }
    }
}
