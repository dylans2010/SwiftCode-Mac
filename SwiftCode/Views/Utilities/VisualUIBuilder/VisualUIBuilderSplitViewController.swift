import AppKit
import SwiftUI

@MainActor
public class VisualUIBuilderSplitViewController: NSSplitViewController {

    public var document: VisualUIDocument {
        if let existing = DocumentCoordinator.shared.visualUIDocument {
            return existing
        }
        let doc = VisualUIDocument()
        DocumentCoordinator.shared.visualUIDocument = doc
        return doc
    }

    private var leftItem: NSSplitViewItem?
    private var centerItem: NSSplitViewItem?
    private var rightItem: NSSplitViewItem?

    override public func viewDidLoad() {
        super.viewDidLoad()

        // Sync Visual UI Document with Active Code Document on load
        if let activeDoc = DocumentCoordinator.shared.activeDocument {
            document.synchronizeFromCode(activeDoc.content)
            document.filePath = activeDoc.url.path
            document.isDirty = activeDoc.isDirty
        }

        setupSplitView()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        // 1. Left Sidebar View (Native AppKit Outline View Controller)
        let leftVC = VisualUIBuilderSidebarViewController(document: document)
        let leftItem = NSSplitViewItem(sidebarWithViewController: leftVC)
        leftItem.minimumThickness = 240
        leftItem.maximumThickness = 320
        leftItem.holdingPriority = .defaultLow + 10
        self.leftItem = leftItem
        addSplitViewItem(leftItem)

        // 2. Center Live Workspace View (Canvas & Previews)
        let centerVC = NSHostingController(rootView: VisualUIBuilderCenterWrapper(document: document))
        centerVC.sizingOptions = []
        centerVC.view.autoresizingMask = [.width, .height]
        let centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.minimumThickness = 500
        centerItem.holdingPriority = .defaultLow - 10
        self.centerItem = centerItem
        addSplitViewItem(centerItem)

        // 3. Right Inspector Panel
        let rightVC = NSHostingController(rootView: VisualUIBuilderInspectorWrapper(document: document))
        rightVC.sizingOptions = []
        rightVC.view.autoresizingMask = [.width, .height]
        let rightItem = NSSplitViewItem(viewController: rightVC)
        rightItem.minimumThickness = 280
        rightItem.maximumThickness = 350
        rightItem.holdingPriority = .defaultLow + 20
        self.rightItem = rightItem
        addSplitViewItem(rightItem)
    }

    public func toggleLeftSidebar(_ sender: Any?) {
        leftItem?.isCollapsed.toggle()
    }

    public func toggleRightInspector(_ sender: Any?) {
        rightItem?.isCollapsed.toggle()
    }
}

// SwiftUI wrappers to embed inside NSHostingControllers cleanly, sharing a single unified document:
struct VisualUIBuilderSidebarWrapper: View {
    let document: VisualUIDocument
    @State private var leftSidebarTab = 0

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .environment(document)
    }
}

struct VisualUIBuilderCenterWrapper: View {
    let document: VisualUIDocument
    @State private var settings = VisualUISettings.shared

    var body: some View {
        VStack(spacing: 0) {
            VisualUIToolbar(document: document, settings: settings)
            Divider()
            HSplitView {
                VisualUICanvasView(document: document, settings: settings)
                    .frame(minWidth: 350)
                VisualUIPreviewPanel(document: document, settings: settings)
                    .frame(minWidth: 350)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(document)
        .environment(settings)
    }
}

struct VisualUIBuilderInspectorWrapper: View {
    let document: VisualUIDocument
    @State private var rightInspectorTab = 0

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .environment(document)
    }
}
