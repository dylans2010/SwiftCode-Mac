import SwiftUI

@MainActor
struct PreviewCanvasView: View {
    @State private var manager = PreviewManager.shared
    @State private var rotateValue = 0.0

    private var activeSessionContent: String {
        guard let path = manager.activeSession?.sourceFilePath else { return "" }
        return (try? String(contentsOfFile: path)) ?? ""
    }

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
                .liquidGlass(style: .subtle, cornerRadius: 12)
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
                            VStack {
                                if let hostedView = manager.hostedView {
                                    PreviewContainer(state: manager.state) {
                                        NativePreviewHost(hostedView: hostedView)
                                    }
                                } else {
                                    PreviewContainer(state: manager.state) {
                                        DynamicSwiftUIPreviewRenderer(content: activeSessionContent)
                                    }
                                }
                            }
                            .padding(32)
                        }
                        .liquidGlass(style: .standard, cornerRadius: 8)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        }
        .simulatorWorkspaceEmbedded()
    }
}
