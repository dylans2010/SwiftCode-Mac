import SwiftUI

/// Preview panel displaying real-time rendering using the modernized PreviewEngine and PreviewHost.
/// Visual UI Builder acts as a pure client of the Preview Engine, generating SwiftUI source code and delegating execution.
public struct VisualUIPreviewPanel: View {
    let document: VisualUIDocument
    let settings: VisualUISettings

    @State private var showingDiagnostics = false
    @State private var previewState = PreviewManager.shared.state

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
                    // Diagnostic Logs & Rendering Metrics from performance monitor
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Rendering Diagnostics")
                                    .font(.headline)
                                Spacer()
                                Button("Clear") {
                                    PreviewDiagnostics.shared.clearLogs()
                                }
                                .buttonStyle(.borderless)
                            }

                            Divider()

                            let monitor = PreviewPerformanceMonitor.shared
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Average Compile Time: \(String(format: "%.3f", monitor.averageCompileTime))s")
                                Text("Average Render Time: \(String(format: "%.3f", monitor.averageRenderTime))s")
                                Text("Total Renders: \(monitor.totalRenders)")
                                Text("Cache Hit Rate: \(String(format: "%.1f", monitor.cacheHitRate * 100))%")
                            }
                            .font(.system(.subheadline, design: .monospaced))
                            .padding(.bottom, 8)

                            Divider()

                            ForEach(PreviewDiagnostics.shared.logs) { log in
                                HStack {
                                    Text(log.category.uppercased())
                                        .bold()
                                        .foregroundColor(log.category == "error" ? .red : .blue)
                                    Text(log.message)
                                }
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                    }
                } else {
                    // Render Active Artboard Preview Environment using PreviewHost & PreviewContainer
                    if let activeID = document.scene.activeArtboardID,
                       let activeArtboard = document.scene.artboards.first(where: { $0.id == activeID }) {
                        ScrollView([.horizontal, .vertical]) {
                            VStack {
                                if let hostedView = PreviewManager.shared.hostedView {
                                    PreviewContainer(state: previewState) {
                                        NativePreviewHost(hostedView: hostedView)
                                    }
                                } else {
                                    // Fallback to high-fidelity live preview runtime workspace
                                    PreviewContainer(state: previewState) {
                                        VisualUIRenderer(rootNode: activeArtboard.rootNode, document: document)
                                    }
                                }
                            }
                            .padding(32)
                        }
                        .task {
                            await refreshPreviewSession()
                        }
                        .onChange(of: document.scene.selectedNodeIDs) { _, _ in
                            Task {
                                await refreshPreviewSession()
                            }
                        }
                        .onChange(of: settings.showCompiledView) { _, _ in
                            Task {
                                await refreshPreviewSession()
                            }
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

    private func generateCurrentSwiftUISource() -> String {
        let generator = VisualUICodeGenerator()
        return generator.generateCode(for: document.scene, targetFramework: .swiftUI)
    }

    private func refreshPreviewSession() async {
        if settings.showCompiledView {
            // Use active editor document
            if let activeDoc = DocumentCoordinator.shared.activeDocument {
                let (preparedCode, targetView) = SwiftViewDetector.prepareSourceCode(activeDoc.content, filename: activeDoc.url.path)
                let resolvedTarget = targetView ?? "SwiftUI Preview"
                await PreviewManager.shared.startPreviewSession(
                    sourcePath: activeDoc.url.path,
                    sourceCode: preparedCode,
                    targetView: resolvedTarget
                )
            }
        } else {
            // Use placeholder project code
            let code = generateCurrentSwiftUISource()
            await PreviewManager.shared.startPreviewSession(
                sourcePath: "VisualUIExportView.swift",
                sourceCode: code,
                targetView: "VisualUIExportView"
            )
        }
    }
}
