import Foundation

public enum SDKLivePreviewViewOpener {
    public static let viewID = "preview.live"

    public static func register() async {
        await SDKViewOpener.shared.register(viewID: viewID) {
            try await SDKViewHostRegistry.shared.open(viewID: viewID)
        }
    }
}
