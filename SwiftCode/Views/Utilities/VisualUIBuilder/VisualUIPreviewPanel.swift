import SwiftUI

/// Preview panel displaying real-time rendering using the modernized PreviewEngine and PreviewHost.
/// Visual UI Builder acts as a pure client of the Preview Engine, generating SwiftUI source code and delegating execution.
public struct VisualUIPreviewPanel: View {
    let document: VisualUIDocument
    let settings: VisualUISettings

    @State private var showingDiagnostics = false
    @State private var previewState = PreviewManager.shared.state
    @State private var isProcessStarted = false

    public var body: some View {
        VStack(spacing: 0) {
            if !isProcessStarted {
                VStack(spacing: 16) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                    Text("Visual UI Builder")
                        .font(.title2.bold())
                    Text("Compiler tasks and simulator preview runtimes are stopped. Press 'Start Process' to build your SwiftUI canvas on-demand.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button {
                        isProcessStarted = true
                        Task {
                            await refreshPreviewSession()
                            if let activeID = document.scene.activeArtboardID,
                               let activeArtboard = document.scene.artboards.first(where: { $0.id == activeID }) {
                                await compileArtboardSource(activeArtboard)
                            }
                        }
                    } label: {
                        Label("Start Process", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
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
                                    let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(activeDoc.content, filename: activeDoc.url.path)
                                    await PreviewManager.shared.startFreshLivePreviewSession(
                                        sourcePath: activeDoc.url.path,
                                        sourceCode: preparedCode,
                                        targetViewName: newValue
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
                    PreviewLogsView()
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
                            // Premium structured diagnostics panel with Retry support
                            PreviewDiagnosticsPanel(session: PreviewManager.shared.activeSession) {
                                Task {
                                    if let activeDoc = DocumentCoordinator.shared.activeDocument {
                                        let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(activeDoc.content, filename: activeDoc.url.path)
                                        await PreviewManager.shared.startFreshLivePreviewSession(
                                            sourcePath: activeDoc.url.path,
                                            sourceCode: preparedCode,
                                            targetViewName: PreviewManager.shared.selectedPreviewName
                                        )
                                    }
                                }
                            }
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
                                                HStack {
                                                    Label("Artboard Compile Error", systemImage: "exclamationmark.triangle.fill")
                                                        .font(.headline)
                                                        .foregroundColor(.red)
                                                    Spacer()
                                                    CopyLogsButton(logs: errorMsg)
                                                }
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
    }



    private func compileArtboardSource(_ artboard: VisualUIArtboard) async {
        guard isProcessStarted else { return }
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
        guard isProcessStarted else { return }
        if let activeDoc = DocumentCoordinator.shared.activeDocument {
            let resolvedTarget = PreviewManager.shared.selectedPreviewName ?? "ContentView"
            let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(activeDoc.content, filename: activeDoc.url.path)
            await PreviewManager.shared.startFreshLivePreviewSession(
                sourcePath: activeDoc.url.path,
                sourceCode: preparedCode,
                targetViewName: resolvedTarget
            )
        }
    }
}

// MARK: - Premium Diagnostics UI Panel

@MainActor
struct PreviewDiagnosticsPanel: View {
    let session: PreviewSession?
    let onRetry: () -> Void

    @State private var showingRawLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Preview Build Pipeline Error", systemImage: "xmark.octagon.fill")
                    .font(.title2.bold())
                    .foregroundColor(.red)
                Spacer()

                Button(action: onRetry) {
                    Label("Retry Build", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.purple)
            }

            Divider()

            // Session Environment Grid
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    HStack {
                        Text("Current Stage:").bold().foregroundStyle(.secondary)
                        Text(session?.status ?? "Unknown")
                    }
                    HStack {
                        Text("Current Project:").bold().foregroundStyle(.secondary)
                        Text(session?.activeProject ?? "None")
                    }
                }
                GridRow {
                    HStack {
                        Text("Current Scheme:").bold().foregroundStyle(.secondary)
                        Text(session?.activeScheme ?? "None")
                    }
                    HStack {
                        Text("Current Preview:").bold().foregroundStyle(.secondary)
                        Text(session?.targetViewName ?? "None")
                    }
                }
                GridRow {
                    HStack {
                        Text("Configuration:").bold().foregroundStyle(.secondary)
                        Text(session?.buildConfig ?? "Debug")
                    }
                    HStack {
                        Text("Timestamp:").bold().foregroundStyle(.secondary)
                        Text(session?.lastCompiledAt.formatted() ?? "N/A")
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)

            // Structured Errors / Compiler Diagnostics
            if let diagnostics = session?.diagnostics, !diagnostics.isEmpty {
                Text("Structured Errors")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(diagnostics) { diag in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text("\(diag.stage) - \(diag.subsystem)")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text(diag.severity.uppercased())
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(diag.severity == "error" ? Color.red.opacity(0.15) : Color.orange.opacity(0.15))
                                        .foregroundColor(diag.severity == "error" ? .red : .orange)
                                        .cornerRadius(4)
                                }

                                if let file = diag.file {
                                    Text("File: \(file)\(diag.line.map { ":\($0)" } ?? "")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(diag.description)
                                    .font(.body)
                                    .padding(.vertical, 2)

                                if let fix = diag.suggestedFix {
                                    Text("Suggested Fix: \(fix)")
                                        .font(.caption)
                                        .italic()
                                        .foregroundColor(.green)
                                }
                            }
                            .padding()
                            .background(Color.red.opacity(0.05))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.red.opacity(0.15), lineWidth: 1)
                            )
                        }
                    }
                }
                .frame(maxHeight: 250)
            }

            // Raw logs & actions
            HStack {
                Button(showingRawLogs ? "Hide Raw Logs" : "Show Raw Logs") {
                    showingRawLogs.toggle()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: copyLogs) {
                    Label("Copy Logs", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button(action: exportLogs) {
                    Label("Export Logs", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            if showingRawLogs {
                ScrollView {
                    Text(PreviewManager.shared.buildLogs.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(6)
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1))
        .padding(20)
    }

    private func copyLogs() {
        let text = PreviewManager.shared.buildLogs.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "preview_build_logs.txt"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let text = PreviewManager.shared.buildLogs.joined(separator: "\n")
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
