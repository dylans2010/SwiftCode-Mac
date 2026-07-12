import SwiftUI

struct SimulatorPreviewView: View {
    @State private var previewManager = PreviewManager.shared

    var body: some View {
        HSplitView {
            // Left properties and targets discoverer list
            VStack(alignment: .leading, spacing: 14) {
                Text("SwiftUI Targets")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top)

                Divider()

                if previewManager.availablePreviews.isEmpty {
                    ContentUnavailableView {
                        Label("No Previews Found", systemImage: "eye.slash")
                    } description: {
                        Text("Open a file containing an active preview declaration.")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(selection: $previewManager.selectedPreviewName) {
                        ForEach(previewManager.availablePreviews, id: \.self) { target in
                            HStack {
                                Image(systemName: "play.square")
                                    .foregroundColor(.purple)
                                Text(target)
                                    .font(.subheadline.bold())
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .tag(target)
                        }
                    }
                    .listStyle(.sidebar)
                }

                Divider()

                // Console logging for previews
                PreviewConsoleView()
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)

            // Right canvas rendering
            PreviewCanvasView()
                .padding()
                .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity)
        }
    }
}
