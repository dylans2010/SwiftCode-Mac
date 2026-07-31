import SwiftUI

@MainActor
struct PreviewCanvasView: View {
    @State private var manager = PreviewManager.shared
    @State private var rotateValue = 0.0

    var body: some View {
        VStack(spacing: 20) {
            PreviewConfigurationView()

            if manager.availablePreviews.isEmpty {
                ContentUnavailableView {
                    Label("No Previews Found", systemImage: "eye.slash")
                } description: {
                    Text("Open a SwiftUI View file containing a #Preview macro or PreviewProvider definition.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(12)
            } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("SwiftUI Live Canvas Rendering", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        ScrollView([.horizontal, .vertical]) {
                            PreviewDeviceFrameView(
                                deviceName: manager.state.currentDevice,
                                isPortrait: manager.state.isPortrait,
                                isDarkMode: manager.state.isDarkMode,
                                scale: manager.state.scale
                            ) {
                                DynamicSwiftUIPreviewRenderer(content: manager.activeSession?.sourceFilePath.flatMap { try? String(contentsOfFile: $0) } ?? "")
                            }
                            .padding(32)
                        }
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        }
        .simulatorWorkspaceEmbedded()
    }
}
