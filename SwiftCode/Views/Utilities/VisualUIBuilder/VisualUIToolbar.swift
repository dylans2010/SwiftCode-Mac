import SwiftUI

/// Elegant workspace toolbar providing configuration selectors, frame builders, dark mode overrides, and quick actions.
public struct VisualUIToolbar: View {
    @Bindable var document: VisualUIDocument
    @Bindable var settings: VisualUISettings

    @State private var showingExportSheet = false
    @State private var showingAIAssistantSheet = false

    public var body: some View {
        HStack {
            // Target Framework Selection Picker
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.topleft.filled")
                    .foregroundColor(.accentColor)
                Text("Framework:")
                    .font(.subheadline.bold())

                Picker("", selection: $document.scene.currentFramework) {
                    ForEach(VisualUIFramework.allCases) { framework in
                        Label(framework.rawValue, systemImage: framework.systemIcon)
                            .tag(framework)
                    }
                }
                .frame(width: 130)
                .controlSize(.regular)
            }

            Spacer()

            // Configuration Options (Grid, Dark Mode, device sizes, orientation)
            HStack(spacing: 12) {
                // Device Frames Selection
                Picker("Device Frame", selection: $settings.selectedDevice) {
                    Text("iPhone 16 Pro").tag("iPhone 16 Pro")
                    Text("iPad Pro").tag("iPad Pro")
                    Text("Apple Watch").tag("Apple Watch")
                    Text("Apple Vision Pro").tag("Apple Vision Pro")
                }
                .frame(width: 150)
                .onChange(of: settings.selectedDevice) { _, newValue in
                    updateSelectedDeviceFrames(to: newValue)
                }

                // Light / Dark Mode Override
                Button {
                    settings.isDarkMode.toggle()
                    settings.addLog("Theme switched to \(settings.isDarkMode ? "Dark" : "Light") Mode.")
                } label: {
                    Image(systemName: settings.isDarkMode ? "moon.stars.fill" : "sun.max.fill")
                        .foregroundStyle(settings.isDarkMode ? .purple : .orange)
                }
                .buttonStyle(.bordered)
                .help("Toggle Color Scheme (Light/Dark)")

                // Toggle Grid visibility
                Button {
                    settings.showGrid.toggle()
                } label: {
                    Image(systemName: settings.showGrid ? "grid.diagonal" : "grid")
                }
                .buttonStyle(.bordered)
                .help("Toggle Snap-to-Grid")

                // Safe Areas visualization
                Button {
                    settings.showSafeAreas.toggle()
                } label: {
                    Image(systemName: settings.showSafeAreas ? "iphone.badge.play" : "iphone")
                }
                .buttonStyle(.bordered)
                .help("Toggle Simulated Device Bezels & Safe Areas")
            }

            Spacer()

            // Actions panel: Undo, Redo, AI Assistant, Export View
            HStack(spacing: 12) {
                // Undo
                Button {
                    document.undo()
                    settings.addLog("Undo executed.")
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .disabled(!document.canUndo)
                .help("Undo (⌘Z)")

                // Redo
                Button {
                    document.redo()
                    settings.addLog("Redo executed.")
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.plain)
                .disabled(!document.canRedo)
                .help("Redo (⌘⇧Z)")

                Divider()
                    .frame(height: 16)

                // Ask AI Assistant Prompt Trigger
                Button {
                    showingAIAssistantSheet = true
                } label: {
                    Label("AI Assistant", systemImage: "sparkles")
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.bordered)
                .help("Ask Codex to redesign, optimize or generate SwiftUI screens")

                // Open in SwiftCode Editor
                Button {
                    openInSwiftCodeEditor()
                } label: {
                    Label("Open in Editor", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)
                .help("Open the generated Swift file inside the main editor")

                // Export Options
                Button {
                    showingExportSheet = true
                } label: {
                    Label("Export Code", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingExportSheet) {
            VisualUIExportView(document: document)
        }
        .sheet(isPresented: $showingAIAssistantSheet) {
            VisualUIAIAssistant(document: document)
        }
    }

    private func openInSwiftCodeEditor() {
        let generator = VisualUICodeGenerator()
        let code = generator.generateCode(for: document.scene, targetFramework: .swiftUI)

        let fileManager = FileManager.default
        let projectURL = ProjectSessionStore.shared.activeProject?.directoryURL ?? fileManager.temporaryDirectory
        let fileURL = projectURL.appendingPathComponent("VisualUIExportView.swift")

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
