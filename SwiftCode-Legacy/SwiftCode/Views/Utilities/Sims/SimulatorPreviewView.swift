import SwiftUI

@MainActor
struct SimulatorPreviewView: View {
    @State private var previewManager = PreviewManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("SwiftUI Previews Workspace", systemImage: "eye.fill")
                    .font(.headline)
                    .foregroundColor(.purple)
                Spacer()
            }
            .padding(.bottom, 16)

            HSplitView {
                // Left properties and targets discoverer list
                ScrollView {
                    VStack(spacing: 20) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("SwiftUI Preview Targets", systemImage: "sparkles")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.purple)
                                    Spacer()
                                }

                                if previewManager.availablePreviews.isEmpty {
                                    ContentUnavailableView {
                                        Label("No Previews Found", systemImage: "eye.slash")
                                    } description: {
                                        Text("Open a file containing an active preview declaration.")
                                    }
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(previewManager.availablePreviews, id: \.self) { target in
                                            Button {
                                                previewManager.selectedPreviewName = target
                                            } label: {
                                                HStack {
                                                    Image(systemName: "play.square")
                                                        .foregroundColor(.purple)
                                                    Text(target)
                                                        .font(.subheadline.bold())
                                                        .foregroundStyle(previewManager.selectedPreviewName == target ? .purple : .primary)
                                                    Spacer()
                                                    if previewManager.selectedPreviewName == target {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundStyle(.purple)
                                                    }
                                                }
                                                .padding(8)
                                                .background(previewManager.selectedPreviewName == target ? Color.purple.opacity(0.05) : Color.secondary.opacity(0.04))
                                                .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        PreviewConsoleView()
                    }
                }
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 400)
                .padding(.trailing, 12)

                // Right canvas rendering
                PreviewCanvasView()
                    .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity)
                    .padding(.leading, 12)
            }
        }
        .simulatorWorkspaceEmbedded()
    }
}
