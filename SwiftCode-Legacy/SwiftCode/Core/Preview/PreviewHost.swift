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
