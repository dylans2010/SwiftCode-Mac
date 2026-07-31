import SwiftUI

/// High-polish native SwiftUI wrapper enclosing the PreviewHost with beautiful device chrome borders, scaling, and state controllers.
public struct PreviewContainer<Content: View>: View {
    let state: PreviewState
    let content: Content

    @State private var renderer = PreviewRenderer()
    @State private var calculatedMetrics: PreviewRenderer.ViewportMetrics?

    public init(state: PreviewState, @ViewBuilder content: () -> Content) {
        self.state = state
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let metrics = calculatedMetrics {
                VStack {
                    content
                        .applyPreviewEnvironment(state)
                        .frame(width: metrics.width, height: metrics.height)
                        .background(state.isDarkMode ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
                        .scaleEffect(metrics.scaleFactor)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: metrics.scaleFactor)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.isPortrait)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .task {
                        await recalculateMetrics()
                    }
            }
        }
        .onChange(of: state.currentDevice) { _, _ in Task { await recalculateMetrics() } }
        .onChange(of: state.isPortrait) { _, _ in Task { await recalculateMetrics() } }
        .onChange(of: state.scale) { _, _ in Task { await recalculateMetrics() } }
    }

    private func recalculateMetrics() async {
        let metrics = await renderer.calculateViewport(
            forDevice: state.currentDevice,
            isPortrait: state.isPortrait,
            globalScale: state.scale
        )
        await MainActor.run {
            self.calculatedMetrics = metrics
        }
    }
}
