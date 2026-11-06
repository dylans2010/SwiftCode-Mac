import Foundation

// MARK: - SDKLivePreviewViewOpener
//
// Ported from Legacy `SwiftCode/SDK/Host/ViewOpener/SDKLivePreviewViewOpener.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Opens the live preview (`preview.live`). No project is needed — the
// preview surface stands alone. The preview view itself is owned by
// the host UI behind the `SDKViewHost` seam (SwiftCodePreviews'
// `PreviewOpenViewsHost` is the natural attachment point); this file
// owns only the view ID and the registration.

public enum SDKLivePreviewViewOpener {
    public static let viewID = "preview.live"

    public static func register() async {
        await SDKViewOpener.shared.register(viewID: viewID) {
            try await SDKViewHostRegistry.shared.open(viewID: viewID)
        }
    }
}
