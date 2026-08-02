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

                if settings.showCompiledView && PreviewManager.shared.availablePreviews.count > 1 {
                    Picker("Target", selection: Binding(
                        get: { PreviewManager.shared.selectedPreviewName ?? "" },
                        set: { newValue in
                            PreviewManager.shared.selectedPreviewName = newValue
                            Task {
                                if let activeDoc = DocumentCoordinator.shared.activeDocument {
                                    await PreviewManager.shared.startPreviewSession(
                                        sourcePath: activeDoc.url.path,
                                        sourceCode: activeDoc.content,
                                        targetView: newValue
                                    )
                                }
                            }
                        }
                    )) {
                        ForEach(PreviewManager.shared.availablePreviews, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 140)
                }

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
                    if settings.showCompiledView {
                        if let hostedView = PreviewManager.shared.hostedView {
                            PreviewContainer(state: previewState) {
                                NativePreviewHost(hostedView: hostedView)
                            }
                        } else if PreviewManager.shared.isCompiling {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Compiling SwiftUI View...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // Real compiler error diagnostics
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Compilation Failed", systemImage: "xmark.octagon.fill")
                                    .font(.headline)
                                    .foregroundColor(.red)

                                Divider()

                                ScrollView {
                                    Text(PreviewManager.shared.buildLogs.joined(separator: "\n"))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(8)
                                .background(Color.red.opacity(0.05))
                                .cornerRadius(6)
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1))
                            .padding(20)
                        }
                    } else {
                        // Regular / Custom Artboard View
                        if let activeID = document.scene.activeArtboardID,
                           let activeArtboard = document.scene.artboards.first(where: { $0.id == activeID }) {
                            ScrollView([.horizontal, .vertical]) {
                                VStack {
                                    if let customSource = activeArtboard.customSwiftUISource, !customSource.isEmpty {
                                        if let artboardView = DocumentCoordinator.shared.compiledArtboardViews[activeArtboard.id] {
                                            PreviewContainer(state: previewState) {
                                                NativePreviewHost(hostedView: artboardView)
                                            }
                                        } else if let errorMsg = DocumentCoordinator.shared.compiledArtboardErrors[activeArtboard.id] {
                                            VStack(alignment: .leading, spacing: 12) {
                                                Label("Artboard Compile Error", systemImage: "exclamationmark.triangle.fill")
                                                    .font(.headline)
                                                    .foregroundColor(.red)
                                                Divider()
                                                Text(errorMsg)
                                                    .font(.system(.body, design: .monospaced))
                                                    .foregroundColor(.red)
                                            }
                                            .padding()
                                            .frame(width: 320)
                                            .background(Color.red.opacity(0.05))
                                            .cornerRadius(8)
                                        } else {
                                            VStack(spacing: 12) {
                                                ProgressView()
                                                Text("Compiling Artboard Source...")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .task {
                                                await compileArtboardSource(activeArtboard)
                                            }
                                        }
                                    } else {
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
            }
            .background(Color.secondary.opacity(0.02))
        }
    }

    private func generateCurrentSwiftUISource() -> String {
        let generator = VisualUICodeGenerator()
        return generator.generateCode(for: document.scene, targetFramework: .swiftUI)
    }

    private func compileArtboardSource(_ artboard: VisualUIArtboard) async {
        guard let customSource = artboard.customSwiftUISource, !customSource.isEmpty else { return }

        let targetView = SwiftViewDetector.determinePrimaryView(in: customSource, filename: "Artboard_\(artboard.id).swift") ?? "ContentView"
        let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(customSource, filename: "Artboard_\(artboard.id).swift")

        do {
            let view = try await PreviewRuntime.shared.updateRuntimeSession(
                sourcePath: "Artboard_\(artboard.id).swift",
                sourceCode: preparedCode,
                targetView: targetView
            ) { _ in }
            DocumentCoordinator.shared.compiledArtboardViews[artboard.id] = view
            DocumentCoordinator.shared.compiledArtboardErrors[artboard.id] = nil
        } catch {
            DocumentCoordinator.shared.compiledArtboardViews[artboard.id] = nil
            DocumentCoordinator.shared.compiledArtboardErrors[artboard.id] = error.localizedDescription
        }
    }

    private func refreshPreviewSession() async {
        if settings.showCompiledView {
            // Use active editor document
            if let activeDoc = DocumentCoordinator.shared.activeDocument {
                // Populate available views in PreviewManager
                let detected = SwiftViewDetector.detectViews(in: activeDoc.content)
                PreviewManager.shared.availablePreviews = detected.isEmpty ? ["ContentView"] : detected
                if PreviewManager.shared.selectedPreviewName == nil || !PreviewManager.shared.availablePreviews.contains(PreviewManager.shared.selectedPreviewName!) {
                    PreviewManager.shared.selectedPreviewName = PreviewManager.shared.availablePreviews.first
                }

                let resolvedTarget = PreviewManager.shared.selectedPreviewName ?? "ContentView"
                let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(activeDoc.content, filename: activeDoc.url.path)
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
