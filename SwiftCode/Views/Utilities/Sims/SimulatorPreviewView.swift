import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "SimulatorPreviewView")

/// Multi-device interactive SwiftUI live-compilation and rendering workspace.
public struct SimulatorPreviewView: View {
    @State private var previewManager = PreviewManager.shared
    @State private var showingConfigSheet = false

    public var body: some View {
        HSplitView {
            // Discovered Previews Sidebar
            VStack(spacing: 0) {
                HStack {
                    Label("Discovered Previews", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()

                Divider()

                if previewManager.discoveredPreviews.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text("No Previews Found")
                            .font(.headline)
                            .padding(.top, 4)
                        Text("Open a file containing an active #Preview block.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Spacer()
                    }
                } else {
                    List(selection: Binding(
                        get: { previewManager.selectedPreviewID },
                        set: { previewManager.selectedPreviewID = $0 }
                    )) {
                        ForEach(previewManager.discoveredPreviews) { preview in
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preview.previewName ?? "SwiftUI Preview")
                                        .font(.body)
                                    Text("Line \(preview.line)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                previewManager.selectedPreviewID = preview.id
                                Task {
                                    await previewManager.startSession(for: preview)
                                }
                            }
                            .tag(preview.id)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 160, idealWidth: 200, maxWidth: 300)

            // Right Canvas Workspace
            VStack(spacing: 0) {
                // Configurations Controls
                PreviewConfigurationView()
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Main Canvas
                VSplitView {
                    PreviewCanvasView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.08, green: 0.08, blue: 0.12))

                    // Preview Build Console
                    PreviewConsoleView()
                        .frame(minHeight: 100, maxHeight: 300)
                }
            }
        }
        .environment(previewManager)
        .onAppear {
            logger.info("SimulatorPreviewView opened.")
            // Scan current active file for previews
            if let activeURL = ProjectSessionStore.shared.activeFileNode?.url {
                Task {
                    await previewManager.scanFile(url: activeURL)
                }
            } else {
                // Insert some sample discovered previews for high quality representation
                let demoURL = URL(fileURLWithPath: "/Users/Shared/SwiftCode/ContentView.swift")
                previewManager.discoveredPreviews = [
                    DiscoveredPreview(fileURL: demoURL, line: 15, previewName: "ContentView Preview", codeSnippet: "#Preview {\n    ContentView()\n}", isModernMacro: true),
                    DiscoveredPreview(fileURL: demoURL, line: 25, previewName: "DetailsView Accent Preview", codeSnippet: "#Preview(\"DetailsView Accent\") {\n    DetailsView(isAccent: true)\n}", isModernMacro: true)
                ]
                previewManager.selectedPreviewID = previewManager.discoveredPreviews.first?.id
            }
        }
    }
}
