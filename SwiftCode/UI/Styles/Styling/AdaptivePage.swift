import SwiftUI

public struct AdaptivePage<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) var colorScheme

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            content
                .macDesktopOptimized()
                .onAppear {
                    updateMetrics(size: proxy.size)
                }
                .onChange(of: proxy.size) { _, newSize in
                    updateMetrics(size: newSize)
                }
                .onChange(of: colorScheme) { _, _ in
                    updateMetrics(size: proxy.size)
                }
        }
    }

    private func updateMetrics(size: CGSize) {
        AdaptiveLayoutEngine.shared.updateMetrics(
            width: size.width,
            height: size.height,
            scale: NSScreen.main?.backingScaleFactor ?? 1.0,
            isFullscreen: NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false,
            appearance: colorScheme == .dark ? .dark : .light
        )
    }
}
