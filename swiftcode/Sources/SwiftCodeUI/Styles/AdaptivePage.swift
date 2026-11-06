// Ported from Legacy `SwiftCode/UI/Styles/Styling/AdaptivePage.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim except `.liquidGlass(...)` -> `.background(.thinMaterial, in:
// RoundedRectangle(...))`: no liquidGlass modifier exists in the destination
// (Legacy LiquidGlass.swift is PARTIAL, another scope); this is the destination's
// own card treatment (WorkersMainView.swift precedent).
// Wiring: the app root must inject AdaptiveLayoutEngine.shared as an
// environmentObject (MacDesktopOptimizedModifier reads it) and wrap pages in
// AdaptivePage/AdaptiveDashboardPage/AdaptiveEditorPage/AdaptiveSettingsPage;
// AdaptiveGrid/AdaptiveSplitLayout/AdaptiveSheet are used directly by callers.

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
        DispatchQueue.main.async {
            AdaptiveLayoutEngine.shared.updateMetrics(
                width: size.width,
                height: size.height,
                scale: NSScreen.main?.backingScaleFactor ?? 1.0,
                isFullscreen: NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false,
                appearance: colorScheme == .dark ? .dark : .light
            )
        }
    }
}
