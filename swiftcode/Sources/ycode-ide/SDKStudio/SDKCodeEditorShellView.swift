import AppKit
import SwiftUI

struct SDKVerticalSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    let top: Top
    let bottom: Bottom
    @Binding var isBottomVisible: Bool

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.autosaveName = "SDKCodeEditorConsoleSplit"

        let topHost = NSHostingView(rootView: top)
        let bottomHost = NSHostingView(rootView: bottom)
        context.coordinator.topHost = topHost
        context.coordinator.bottomHost = bottomHost

        splitView.addSubview(topHost)
        if isBottomVisible {
            splitView.addSubview(bottomHost)
            splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        }
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        if let topHost = context.coordinator.topHost {
            topHost.rootView = top
        }
        guard let bottomHost = context.coordinator.bottomHost else { return }
        bottomHost.rootView = bottom

        let isShown = bottomHost.superview != nil
        if isBottomVisible != isShown {
            if isBottomVisible {
                splitView.addSubview(bottomHost)
                splitView.setHoldingPriority(.defaultHigh, forSubviewAt: splitView.subviews.count - 1)
            } else {
                bottomHost.removeFromSuperview()
            }
            splitView.adjustSubviews()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var topHost: NSHostingView<Top>?
        var bottomHost: NSHostingView<Bottom>?
    }
}
