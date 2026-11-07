import AppKit
import SwiftUI

@MainActor
public final class PreviewWindowController: NSWindowController {
    public convenience init<Content: View>(rootView: Content, title: String = "Live SwiftUI Preview") {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 320, height: 480)
        window.isReleasedWhenClosed = false
        window.center()

        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController

        self.init(window: window)
    }
}
