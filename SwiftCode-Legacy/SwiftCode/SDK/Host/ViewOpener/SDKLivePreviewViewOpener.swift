import AppKit
import Foundation
import SwiftUI

@MainActor
public struct SDKLivePreviewViewOpener {
    nonisolated public static let capabilityID: SDKCapabilityID = .previewLive

    private static let window = SDKHostedWindow<ArtboardSimulator>()

    public static func open() {
        window.show(
            rootView: ArtboardSimulator(onClose: { window.close() }),
            title: "Live Preview",
            size: NSSize(width: 420, height: 700),
            autosaveName: "SDKLivePreviewWindow",
            minSize: NSSize(width: 320, height: 500)
        )
    }
}
