import SwiftUI

public struct AdaptivePage<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            content
                .macDesktopOptimized()
                .onAppear {
                    AdaptiveLayoutEngine.shared.updateMetrics(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        scale: NSScreen.main?.backingScaleFactor ?? 1.0,
                        isFullscreen: NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
                    )
                }
                .onChange(of: proxy.size) { _, newSize in
                    AdaptiveLayoutEngine.shared.updateMetrics(
                        width: newSize.width,
                        height: newSize.height,
                        scale: NSScreen.main?.backingScaleFactor ?? 1.0,
                        isFullscreen: NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
                    )
                }
        }
    }
}
