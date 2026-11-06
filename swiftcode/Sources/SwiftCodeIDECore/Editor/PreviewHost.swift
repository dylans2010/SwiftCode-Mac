// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Core/Preview/PreviewHost.swift
//   (Legacy main ab03f681)
//
// Destination: SwiftCodeIDECore/Editor/PreviewHost.swift. Verbatim apart
// from this header and the `#if canImport(AppKit)` guard (see below).
//
// Why SwiftCodeIDECore, not SwiftCodePreviews or SwiftCodeUI:
//   * SwiftCodePreviews already declares `public enum PreviewHost`
//     (the host-process namespace); a second `PreviewHost` in that
//     module would collide.
//   * SwiftCodeUI references the SwiftCodePreviews enum unqualified
//     (`PreviewHost.build`, `PreviewHost.parseReport`,
//     `PreviewHost.Report` in RemotePreviewSession.swift and
//     WorkspaceWindowController+LivePreviews.swift); a `PreviewHost`
//     struct in SwiftCodeUI would shadow it there.
//   * SwiftCodeIDECore has no `PreviewHost` type reference (only the
//     string "SwiftCodePreviewHost"), so the Legacy names land cleanly.
//     Legacy consumers in the Views scope (PreviewCanvasView,
//     ArtboardSimulator, RunFullAppView, VisualUIBuilderSplitViewController,
//     VisualUICanvasView, VisualUIPreviewPanel) use these two wrappers to
//     host SwiftUI content and pre-instantiated AppKit views.
//
// Whole file is `#if canImport(AppKit)`: `NSViewRepresentable` /
// `NSHostingView` do not exist on Linux, and SwiftCodeIDECore also builds
// there (swiftcode-ide). No Linux stub — the types simply do not exist on
// that platform.

#if canImport(AppKit)
import SwiftUI
import AppKit

/// A reusable, highly-optimized AppKit host that wraps and renders actual, live interactive SwiftUI views natively.
public struct PreviewHost<Content: View>: NSViewRepresentable {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public func makeNSView(context: Context) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.autoresizingMask = [.width, .height]
        return hostingView
    }

    public func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.rootView = content
        nsView.needsLayout = true
    }
}

/// A native host that bridges pre-instantiated AppKit views into SwiftUI, utilized by the Dynamic Link Runtime.
public struct NativePreviewHost: NSViewRepresentable {
    public let hostedView: NSView

    public init(hostedView: NSView) {
        self.hostedView = hostedView
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: container.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // Core AppKit layout handles update notifications automatically
        nsView.needsLayout = true
    }
}
#endif
