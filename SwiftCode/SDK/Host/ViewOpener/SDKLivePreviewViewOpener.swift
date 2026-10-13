import AppKit
import Foundation
import SwiftUI

// MARK: - SDKLivePreviewViewOpener
//
// View opener for capability `preview.live` ("Live SwiftUI preview").
//
// ## Which surface opens
// `ArtboardSimulator` (public,
// SwiftCode/Views/Utilities/VisualUIBuilder/ArtboardSimulator.swift,
// `public init(onClose: @escaping () -> Void)`), hosted in an SDK-owned
// `NSWindow` titled "Live Preview". This is the real live-preview surface:
// its Live Preview / Run Full App modes render through the host's managed
// preview pipeline (`PreviewManager.shared`), which the view reads
// internally — the view takes no project parameter and manages its own
// session state, so no project resolution (and no project-missing error)
// applies here.
//
// ## Entry points considered and verified
// - `PreviewWindowController` (`public convenience init<Content: View>
//   (rootView: Content, title: String = "Live SwiftUI Preview")`,
//   SwiftCode/Core/Preview/PreviewWindowController.swift) — VERIFIED DEAD:
//   a repo-wide grep finds zero instantiations. Not wired.
// - `com.swiftcode.openArtboardSimulator` notification — this IS the app's
//   live toggle (posted by `VisualUICanvasView`, observed by `WorkspaceView`
//   which sets `showArtboardSimulator = true` on its trailing slide-over
//   panel). Not used here because it only works while a `WorkspaceView` is
//   on screen observing it; the opener cannot guarantee or detect that, so
//   posting it could be a silent no-op. Hosting the same live
//   `ArtboardSimulator` view in an SDK window always presents the actual
//   surface.
// - `VisualUIBuilderWindowManager.shared.showWindow()` is live but is the
//   Visual UI Builder surface (capability `uibuilder.open`), not the live
//   preview surface, so it is out of scope for this opener.
//
// ## Presentation
// `SDKHostedWindow` (mirroring `SDKStudioWindowManager`): a real `NSWindow`
// + `NSHostingController`; the view's `onClose` closes the window.
//
// ## Verification status
// Statically verified only — no Swift toolchain in this environment.
// Needs `xcodebuild` on Dylan's Mac: target membership of the new file,
// `ArtboardSimulator` init signature, and a live open of the preview window.

@MainActor
public struct SDKLivePreviewViewOpener {
    /// Capability this opener serves: `preview.live`.
    nonisolated public static let capabilityID: SDKCapabilityID = .previewLive

    private static let window = SDKHostedWindow<ArtboardSimulator>()

    /// Opens the live SwiftUI preview surface in its own window.
    /// Always presents a real window; never a silent no-op.
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
