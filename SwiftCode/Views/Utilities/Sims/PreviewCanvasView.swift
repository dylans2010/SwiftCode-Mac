import SwiftUI

struct PreviewCanvasView: View {
    @State private var manager = PreviewManager.shared
    @State private var rotateValue = 0.0

    var body: some View {
        VStack(spacing: 24) {
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
                                deviceName: manager.configuration.deviceName,
                                isPortrait: manager.configuration.isPortrait,
                                isDarkMode: manager.configuration.isDarkMode,
                                scale: manager.scale
                            ) {
                                // Dynamic rendering simulation layer showing active preview
                                VStack(spacing: 20) {
                                    HStack {
                                        Image(systemName: "sparkles")
                                            .foregroundColor(.purple)
                                        Text("SwiftUI Live Preview")
                                            .font(.headline)
                                        Spacer()
                                    }

                                    Divider()

                                    Text("Active Preview Target: '\(manager.selectedPreviewName ?? "None")'")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Image(systemName: "hammer.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.accentColor)
                                        .rotationEffect(Angle(degrees: rotateValue))
                                        .onAppear {
                                            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                                                rotateValue = 360
                                            }
                                        }

                                    Spacer()

                                    Text("Real-time visual feedback compiles continuously as you type.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(24)
                                .background(manager.configuration.isDarkMode ? Color.black : Color.white)
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
    }
}
