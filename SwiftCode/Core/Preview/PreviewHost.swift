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
