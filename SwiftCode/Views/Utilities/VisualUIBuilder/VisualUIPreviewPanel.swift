import SwiftUI

/// Preview panel displaying real-time rendering, side-by-side device targets, environment overrides, and diagnostic logs.
public struct VisualUIPreviewPanel: View {
    let document: VisualUIDocument
    let settings: VisualUISettings

    @State private var showingDiagnostics = false

    public var body: some View {
        VStack(spacing: 0) {
            // Preview sub-toolbar
            HStack {
                Text("LIVE VIEWPORT")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showingDiagnostics.toggle()
                } label: {
                    Label("Diagnostics", systemImage: "heart.text.square")
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ZStack {
                if showingDiagnostics {
                    // Diagnostic Logs & Rendering Metrics
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Rendering Diagnostics")
                                    .font(.headline)
                                Spacer()
                                Button("Clear") {
                                    settings.clearLogs()
                                }
                                .buttonStyle(.borderless)
                            }

                            Divider()

                            ForEach(settings.diagnosticsLogs, id: \.self) { log in
                                Text(log)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                    }
                } else {
                    // Render Active Artboard Preview Environment
                    if let activeID = document.scene.activeArtboardID,
                       let artboard = document.scene.artboards.first(where: { $0.id == activeID }) {
                        ScrollView([.horizontal, .vertical]) {
                            VStack {
                                VisualUIRenderer(rootNode: artboard.rootNode, document: document)
                                    .padding(32)
                                    .background(settings.isDarkMode ? Color.black : Color.white)
                                    .cornerRadius(16)
                                    .shadow(radius: 8)
                                    .scaleEffect(0.9)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("No Active Artboard", systemImage: "macwindow")
                        }
                    }
                }
            }
            .background(Color.secondary.opacity(0.02))
        }
    }
}
