import SwiftUI

/// High-polish native SwiftUI wrapper enclosing the PreviewHost with beautiful, clean device boundaries and environment controllers.
/// No fake notches, Dynamic Islands, status bars, or screenshot mockups are rendered.
public struct PreviewContainer<Content: View>: View {
    let state: PreviewState
    let content: Content

    @State private var calculatedMetrics: PreviewDeviceConfig?

    public init(state: PreviewState, @ViewBuilder content: () -> Content) {
        self.state = state
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let metrics = calculatedMetrics {
                let w = state.isPortrait ? metrics.width : metrics.height
                let h = state.isPortrait ? metrics.height : metrics.width

                VStack {
                    content
                        .applyPreviewEnvironment(state)
                        .frame(width: w, height: h)
                        .background(state.isDarkMode ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 2.0)
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
                        .scaleEffect(state.scale)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.scale)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.isPortrait)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .onAppear {
                        recalculateMetrics()
                    }
            }
        }
        .onChange(of: state.currentDevice) { _, _ in recalculateMetrics() }
        .onChange(of: state.isPortrait) { _, _ in recalculateMetrics() }
    }

    private func recalculateMetrics() {
        let metrics = PreviewDeviceManager.shared.device(named: state.currentDevice)
        self.calculatedMetrics = metrics
    }
}
