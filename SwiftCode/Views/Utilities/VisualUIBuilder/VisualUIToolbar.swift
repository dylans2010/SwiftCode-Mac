import SwiftUI

/// Elegant workspace toolbar providing configuration selectors, frame builders, dark mode overrides, and quick actions.
public struct VisualUIToolbar: View {
    @Bindable var document: VisualUIDocument
    @Bindable var settings: VisualUISettings

    @State private var showingExportSheet = false
    @State private var showingAIAssistantSheet = false

    public init(document: VisualUIDocument, settings: VisualUISettings) {
        self.document = document
        self.settings = settings
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Group 1: Workspace Mode & Framework
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { settings.showCompiledView },
                    set: { settings.showCompiledView = $0 }
                )) {
                    Label("Compiled View", systemImage: "play.desktopcomputer")
                        .font(.subheadline.bold())
                }
                .toggleStyle(.button)
                .help("Toggle between Canvas design mode and live compiled editor document")

                if !settings.showCompiledView {
                    Picker("Framework", selection: $document.scene.currentFramework) {
                        ForEach(VisualUIFramework.allCases) { framework in
                            Text(framework.rawValue).tag(framework)
                        }
                    }
                    .frame(width: 110)
                    .controlSize(.small)
                }
            }

            Spacer()

            // Group 2: Layout & Viewport Configuration
            HStack(spacing: 8) {
                Picker("Device", selection: $settings.selectedDevice) {
                    Text("iPhone 16 Pro").tag("iPhone 16 Pro")
                    Text("iPad Pro").tag("iPad Pro")
                    Text("Apple Watch").tag("Apple Watch")
                    Text("Apple Vision Pro").tag("Apple Vision Pro")
                }
                .frame(width: 140)
                .controlSize(.small)
                .onChange(of: settings.selectedDevice) { _, newValue in
                    updateSelectedDeviceFrames(to: newValue)
                }

                Divider()
                    .frame(height: 16)

                Button {
                    settings.isDarkMode.toggle()
                    settings.addLog("Theme switched to \(settings.isDarkMode ? "Dark" : "Light") Mode.")
                } label: {
                    Image(systemName: settings.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .foregroundColor(settings.isDarkMode ? .purple : .orange)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Toggle Dark/Light Mode")

                Button {
                    settings.showGrid.toggle()
                } label: {
                    Image(systemName: "grid")
                        .foregroundColor(settings.showGrid ? .accentColor : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Toggle Grid")

                Button {
                    settings.showSafeAreas.toggle()
                } label: {
                    Image(systemName: "iphone.badge.play")
                        .foregroundColor(settings.showSafeAreas ? .accentColor : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Toggle Device Bezels & Safe Areas")
            }

            Spacer()

            // Group 3: Document Actions
            HStack(spacing: 12) {
                // Undo / Redo group
                HStack(spacing: 4) {
                    Button {
                        document.undo()
                        settings.addLog("Undo executed.")
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!document.canUndo)
                    .help("Undo (⌘Z)")

                    Button {
                        document.redo()
                        settings.addLog("Redo executed.")
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!document.canRedo)
                    .help("Redo (⌘⇧Z)")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Divider()
                    .frame(height: 16)

                // Sparkles AI Assistant
                Button {
                    showingAIAssistantSheet = true
                } label: {
                    Label("AI Assistant", systemImage: "sparkles")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
                .help("Ask Codex AI Assistant")

                // Overflow Menu for Exporting / Code actions
                Menu {
                    Button {
                        openInSwiftCodeEditor()
                    } label: {
                        Label("Open in Editor", systemImage: "chevron.left.forwardslash.chevron.right")
                    }

                    Button {
                        showingExportSheet = true
                    } label: {
                        Label("Export Code...", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .frame(width: 80)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingExportSheet) {
            VisualUIExportView(document: document)
        }
        .sheet(isPresented: $showingAIAssistantSheet) {
            VisualUIAIAssistant(document: document)
        }
    }

    private func openInSwiftCodeEditor() {
        let code: String

        // Find if we are rendering a custom artboard with custom SwiftUI source code!
        if let activeID = document.scene.activeArtboardID,
           let activeArtboard = document.scene.artboards.first(where: { $0.id == activeID }),
           let customSource = activeArtboard.customSwiftUISource, !customSource.isEmpty {
            code = customSource
        } else if settings.showCompiledView, let activeDoc = DocumentCoordinator.shared.activeDocument {
            code = activeDoc.content
        } else {
            let generator = VisualUICodeGenerator()
            code = generator.generateCode(for: document.scene, targetFramework: .swiftUI)
        }

        let fileURL: URL
        if let activeDoc = DocumentCoordinator.shared.activeDocument {
            fileURL = activeDoc.url
        } else {
            let projectURL = ProjectSessionStore.shared.activeProject?.directoryURL ?? FileManager.default.temporaryDirectory
            fileURL = projectURL.appendingPathComponent("VisualUIExportView.swift")
        }

        do {
            try code.write(to: fileURL, atomically: true, encoding: .utf8)
            document.filePath = fileURL.path
            document.isDirty = false

            if let activeProject = ProjectSessionStore.shared.activeProject {
                ProjectSessionStore.shared.refreshFileTree(for: activeProject)
            }

            settings.addLog("Saved latest generated SwiftUI code to \(fileURL.lastPathComponent)")

            NotificationCenter.default.post(
                name: NSNotification.Name("com.swiftcode.openFileInWorkspace"),
                object: nil,
                userInfo: ["filePath": fileURL.path]
            )

            // Close the Visual UI Builder window to bring editor back to the foreground
            VisualUIBuilderWindowManager.shared.closeWindow()

            settings.addLog("Dispatched notification to open \(fileURL.lastPathComponent) in editor.")
        } catch {
            settings.addLog("Error opening in editor: \(error.localizedDescription)")
        }
    }

    private func updateSelectedDeviceFrames(to device: String) {
        document.checkpoint()
        for artboard in document.scene.artboards {
            artboard.deviceFrame = device
        }
        settings.addLog("Updated device frame of active artboards to \(device).")
    }
}
