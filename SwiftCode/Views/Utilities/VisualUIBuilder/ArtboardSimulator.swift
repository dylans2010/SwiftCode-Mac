import SwiftUI
import AppKit

public struct ArtboardSimulator: View {
    @State private var mode: Int = 0 // 0: Live Preview, 1: Run Full App
    @State private var zoomScale: CGFloat = 1.0

    var onClose: () -> Void

    @MainActor
    private var previewManager: PreviewManager {
        PreviewManager.shared
    }

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            // High-fidelity Simulator Header & Segment Selector
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "macwindow.on.rectangle")
                            .foregroundColor(.accentColor)
                        Text("Artboard Simulator")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    // Exit action button
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Simulator (Exit)")
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Mode picker segment
                Picker("Execution Mode", selection: $mode) {
                    Text("Live Preview").tag(0)
                    Text("Run Full App").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if mode == 0 {
                LivePreviewSubView()
            } else {
                RunFullAppView()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Live Preview SubView

struct LivePreviewSubView: View {
    @State private var zoomScale: Double = 1.0
    @State private var showingLogs = false

    @MainActor
    private var previewManager: PreviewManager {
        PreviewManager.shared
    }

    var body: some View {
        VStack(spacing: 0) {
            // Premium Sub-Toolbar containing Refresh, Start New Session, Exit
            HStack(spacing: 12) {
                // Refresh Button
                Button {
                    Task {
                        await triggerRefresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.accentColor)
                .help("Recompile and rerender active PreviewSession")

                // Start New Session Button
                Button {
                    Task {
                        await triggerStartNewSession()
                    }
                } label: {
                    Label("New Session", systemImage: "play.circle")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Discard active session and start a brand-new one")

                Spacer()

                // Target View Selector
                if !previewManager.availablePreviews.isEmpty {
                    Picker("Target", selection: Binding(
                        get: { previewManager.selectedPreviewName ?? "" },
                        set: { newValue in
                            previewManager.selectedPreviewName = newValue
                            Task {
                                await triggerRefresh()
                            }
                        }
                    )) {
                        ForEach(previewManager.availablePreviews, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 130)
                    .labelsHidden()
                }

                // Logs/Diagnostics Toggle
                Button {
                    showingLogs.toggle()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundColor(showingLogs ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Diagnostics Logs")
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main Content Area with state preservation/restoration
            ZStack {
                if showingLogs {
                    PreviewLogsView()
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        VStack {
                            if let activeID = DocumentCoordinator.shared.visualUIDocument?.scene.activeArtboardID,
                               let activeArtboard = DocumentCoordinator.shared.visualUIDocument?.scene.artboards.first(where: { $0.id == activeID }),
                               activeArtboard.name != "Default" {
                                // Render active custom artboard
                                if let customSource = activeArtboard.customSwiftUISource, !customSource.isEmpty {
                                    if let artboardView = DocumentCoordinator.shared.compiledArtboardViews[activeArtboard.id] {
                                        NativePreviewHost(hostedView: artboardView)
                                            .padding(16)
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
                                        .background(Color.red.opacity(0.05))
                                        .cornerRadius(8)
                                        .padding(16)
                                    } else {
                                        VStack(spacing: 12) {
                                            ProgressView()
                                            Text("Compiling Artboard...")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(32)
                                    }
                                } else {
                                    // Visual Renderer
                                    if let document = DocumentCoordinator.shared.visualUIDocument {
                                        VisualUIRenderer(rootNode: activeArtboard.rootNode, document: document)
                                            .padding(16)
                                    }
                                }
                            } else {
                                // Render default active PreviewManager compiled view
                                if let hostedView = previewManager.hostedView {
                                    NativePreviewHost(hostedView: hostedView)
                                        .padding(16)
                                } else if previewManager.isCompiling {
                                    VStack(spacing: 12) {
                                        ProgressView()
                                        Text("Compiling SwiftUI View...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(32)
                                } else {
                                    // Compile error diagnostics or empty state
                                    if !previewManager.buildLogs.isEmpty {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Label("Compilation Failed", systemImage: "xmark.octagon.fill")
                                                .font(.headline)
                                                .foregroundColor(.red)

                                            Divider()

                                            ScrollView {
                                                Text(previewManager.buildLogs.joined(separator: "\n"))
                                                    .font(.system(.body, design: .monospaced))
                                                    .foregroundColor(.primary)
                                            }
                                            .frame(maxHeight: 250)
                                        }
                                        .padding()
                                        .background(Color.red.opacity(0.05))
                                        .cornerRadius(8)
                                        .padding(16)
                                    } else {
                                        ContentUnavailableView {
                                            Label("No Active Preview", systemImage: "play.slash")
                                        } description: {
                                            Text("Open a SwiftUI file or start a Preview session to begin.")
                                        }
                                        .padding(32)
                                    }
                                }
                            }
                        }
                        .scaleEffect(zoomScale)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Zoom Control HUD
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Button { zoomScale = max(0.5, zoomScale - 0.1) } label: { Image(systemName: "minus") }
                        .buttonStyle(.plain)
                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption.monospacedDigit())
                    Button { zoomScale = min(2.0, zoomScale + 0.1) } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .padding(6)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    // Save editor buffers immediately before compilation
    private func saveEditorBuffers() async {
        if let activeDoc = DocumentCoordinator.shared.activeDocument {
            do {
                try await TextBufferEngine.shared.save(content: activeDoc.content, to: activeDoc.url)
                DocumentCoordinator.shared.updateUnsavedStatus(isDirty: false)
            } catch {
                PreviewDiagnostics.shared.addLog(category: "error", message: "Failed to auto-save editor changes: \(error.localizedDescription)")
            }
        }
    }

    private func triggerRefresh() async {
        await saveEditorBuffers()

        guard let activeDoc = DocumentCoordinator.shared.activeDocument else { return }
        let parsed = PreviewBlockParser.parsePreviews(in: activeDoc.content)
        let detected = parsed.isEmpty ? SwiftViewDetector.detectViews(in: activeDoc.content) : parsed.map { $0.title }
        previewManager.availablePreviews = detected

        let targetView = previewManager.selectedPreviewName ?? detected.first ?? "ContentView"
        await previewManager.refreshActiveSession(
            sourcePath: activeDoc.url.path,
            sourceCode: activeDoc.content,
            targetView: targetView
        )
    }

    private func triggerStartNewSession() async {
        await saveEditorBuffers()

        guard let activeDoc = DocumentCoordinator.shared.activeDocument else { return }
        let parsed = PreviewBlockParser.parsePreviews(in: activeDoc.content)
        let detected = parsed.isEmpty ? SwiftViewDetector.detectViews(in: activeDoc.content) : parsed.map { $0.title }
        previewManager.availablePreviews = detected

        let targetView = previewManager.selectedPreviewName ?? detected.first ?? "ContentView"
        await previewManager.startNewSession(
            sourcePath: activeDoc.url.path,
            sourceCode: activeDoc.content,
            targetView: targetView
        )
    }
}
