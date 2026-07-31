import SwiftUI
import AppKit

/// Main entry point for the Visual UI Builder.
/// Reuses the high-polish split-panel organization of NSPersonalDocumentationView.
public struct VisualUIBuilderView: View {
    @State private var document = VisualUIDocument()
    @State private var settings = VisualUISettings.shared

    // Panel collapse toggles
    @State private var showLeftSidebar = true
    @State private var showRightInspector = true

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Workspace Toolbar
            VisualUIToolbar(document: document, settings: settings)

            Divider()

            // Desktop split layout matching NSPersonalDocumentation organization
            HStack(spacing: 0) {
                // Panel 1: Left Workspace Sidebar (Component Library & Scene Hierarchy)
                if showLeftSidebar {
                    VStack(spacing: 0) {
                        Picker("Left Sidebar Section", selection: $leftSidebarTab) {
                            Text("Library").tag(0)
                            Text("Hierarchy").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(8)

                        Divider()

                        if leftSidebarTab == 0 {
                            VisualUIComponentLibrary(document: document)
                        } else {
                            VisualUIHierarchy(document: document)
                        }
                    }
                    .frame(width: 260)
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(.move(edge: .leading))

                    Divider()
                }

                // Panel 2: Interactive Main Canvas & Live Preview Viewport
                VStack(spacing: 0) {
                    HSplitView {
                        // Left-side Infinite Canvas
                        VisualUICanvasView(document: document, settings: settings)
                            .frame(minWidth: 400)

                        // Right-side Live Preview Panel
                        VisualUIPreviewPanel(document: document, settings: settings)
                            .frame(minWidth: 350)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Panel 3: Right Inspector (Properties, Assets, Layers, Animations, Bindings)
                if showRightInspector {
                    Divider()

                    VStack(spacing: 0) {
                        Picker("Inspector Section", selection: $rightInspectorTab) {
                            Image(systemName: "slider.horizontal.3").tag(0) // Properties
                            Image(systemName: "square.3.layers.3d").tag(1)    // Layers/Structure
                            Image(systemName: "folder").tag(2)               // Assets/Colors
                            Image(systemName: "link").tag(3)                 // Bindings & Navigation
                            Image(systemName: "play.circle").tag(4)           // Animations
                        }
                        .pickerStyle(.segmented)
                        .padding(8)

                        Divider()

                        Group {
                            switch rightInspectorTab {
                            case 0:
                                VisualUIInspector(document: document)
                            case 1:
                                VisualUILayersPanel(document: document)
                            case 2:
                                VisualUIAssetsPanel(document: document)
                            case 3:
                                VisualUIBindingsPanel(document: document)
                            default:
                                VisualUIAnimationsPanel(document: document)
                            }
                        }
                    }
                    .frame(width: 300)
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .environment(document)
        .environment(settings)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation {
                        showLeftSidebar.toggle()
                    }
                } label: {
                    Label("Toggle Left Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle Left Workspace Sidebar (⌘ShiftL)")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation {
                        showRightInspector.toggle()
                    }
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
                .help("Toggle Properties Inspector (⌘ShiftI)")
            }
        }
    }

    // Tab state controllers
    @State private var leftSidebarTab = 0
    @State private var rightInspectorTab = 0
}
