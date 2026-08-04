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
            // Group 1: Design Framework selector
            HStack(spacing: 12) {
                Picker("Framework", selection: $document.scene.currentFramework) {
                    ForEach(VisualUIFramework.allCases) { framework in
                        Text(framework.rawValue).tag(framework)
                    }
                }
                .frame(width: 130)
                .controlSize(.small)
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

                // Export actions
                Button {
                    showingExportSheet = true
                } label: {
                    Label("Export Code...", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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



    private func updateSelectedDeviceFrames(to device: String) {
        document.checkpoint()
        for artboard in document.scene.artboards {
            artboard.deviceFrame = device
        }
        settings.addLog("Updated device frame of active artboards to \(device).")
    }
}
