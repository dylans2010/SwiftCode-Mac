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
            if VisualUISettings.shared.showCompiledView {
                document.scene.artboards.removeAll { $0.name == "Home View" && $0.rootNode.children.first?.properties["textValue"] == "Welcome to Visual UI Builder" }

                let name = activeDoc.url.deletingPathExtension().lastPathComponent
                if !document.scene.artboards.contains(where: { $0.name == name }) {
                    let rootNode = VisualComponentNode(type: .vStack)
                    let compiledArtboard = VisualUIArtboard(name: name, deviceFrame: VisualUISettings.shared.selectedDevice, rootNode: rootNode)
                    document.scene.artboards.append(compiledArtboard)
                    document.scene.activeArtboardID = compiledArtboard.id
                }
            } else {
                document.synchronizeFromCode(activeDoc.content)
            }
            document.filePath = activeDoc.url.path
            document.isDirty = activeDoc.isDirty
        }

        setupSplitView()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFullScreenToggle(_:)),
            name: NSNotification.Name("com.swiftcode.visualUIBuilder.toggleFullScreen"),
            object: nil
        )
    }

    @objc private func handleFullScreenToggle(_ notification: Notification) {
        guard let isFull = notification.userInfo?["isFullScreen"] as? Bool else { return }
        leftItem?.isCollapsed = isFull
        rightItem?.isCollapsed = isFull
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
        leftItem.canCollapse = true
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
        rightItem.canCollapse = true
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
    @State private var sidebarState = VisualUIBuilderSidebarState.shared

    var body: some View {
        VStack(spacing: 0) {
            VisualUIToolbar(document: document, settings: settings)
            Divider()

            if sidebarState.selectedIndex == 2 {
                SavedArtboardsWorkspaceView(document: document)
            } else {
                VisualUICanvasView(document: document, settings: settings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(document)
        .environment(settings)
    }
}

public enum ModernInspectorSection: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case properties = "Properties"
    case preview = "Preview"
    case diagnostics = "Diagnostics"
    case runtime = "Runtime"
    case build = "Build"
    case environment = "Environment"
    case logs = "Logs"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .general: return "info.circle"
        case .properties: return "slider.horizontal.3"
        case .preview: return "eye"
        case .diagnostics: return "waveform.path.ecg"
        case .runtime: return "play.circle"
        case .build: return "hammer"
        case .environment: return "globe"
        case .logs: return "doc.text"
        }
    }
}

struct VisualUIBuilderInspectorWrapper: View {
    let document: VisualUIDocument
    @State private var settings = VisualUISettings.shared

    // Persist and remember the last selected section while the inspector remains open
    @AppStorage("com.swiftcode.workspace.lastSelectedInspectorSection")
    private var selectedSectionRaw = ModernInspectorSection.properties.rawValue

    private var selectedSection: ModernInspectorSection {
        get { ModernInspectorSection(rawValue: selectedSectionRaw) ?? .properties }
        nonisolated(unsafe) set { selectedSectionRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Native SwiftUI Picker as navigation control
            HStack {
                Label("Inspector:", systemImage: "sidebar.trailing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { selectedSection },
                    set: { selectedSection = $0 }
                )) {
                    ForEach(ModernInspectorSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
                .pickerStyle(.automatic)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // State preservation when switching between sections is achieved using a ZStack with opacity
            ZStack {
                // Properties Section
                VisualUIInspector(document: document)
                    .opacity(selectedSection == .properties ? 1 : 0)
                    .disabled(selectedSection != .properties)

                // General Section (Identical wrapper or metadata)
                VStack(spacing: 12) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("General Info", systemImage: "info.circle")
                                .font(.headline)
                            Text("Visual Workspace Engine")
                                .font(.subheadline.bold())
                            Text("Provides interactive preview compilation and high fidelity layout rendering using a native sandboxed AppKit and SwiftUI workspace container.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Divider()

                            HStack {
                                Text("File Path:")
                                    .bold()
                                Spacer()
                            }
                            Text(document.filePath ?? "In-Memory / Sandbox Document")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)

                            HStack {
                                Text("Modified Status:")
                                    .bold()
                                Spacer()
                                Text(document.isDirty ? "Unsaved Changes" : "Saved")
                                    .foregroundColor(document.isDirty ? .orange : .green)
                                    .bold()
                            }
                            .font(.caption)
                        }
                        .padding()
                    }
                }
                .opacity(selectedSection == .general ? 1 : 0)
                .disabled(selectedSection != .general)

                // Preview Section
                VStack(spacing: 12) {
                    if let hostedView = PreviewManager.shared.hostedView {
                        Text("Active Compiled View Hosted")
                            .font(.subheadline.bold())
                            .padding(.top)
                        NativePreviewHost(hostedView: hostedView)
                            .padding()
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .padding()
                    } else {
                        ContentUnavailableView {
                            Label("No Active Preview Host", systemImage: "eye.slash")
                        } description: {
                            Text("Enable 'Show Compiled View' or open a Swift file to run dynamic live preview hosts.")
                        }
                    }
                }
                .opacity(selectedSection == .preview ? 1 : 0)
                .disabled(selectedSection != .preview)

                // Diagnostics Section
                VStack(spacing: 0) {
                    HStack {
                        Label("Diagnostics", systemImage: "waveform.path.ecg")
                            .font(.headline)
                        Spacer()
                        // Copy button using reusable CopyLogsButton
                        CopyLogsButton(logs: {
                            let logs = PreviewDiagnostics.shared.logs.filter { $0.category == "error" }
                            return logs.map { "[\($0.category.uppercased())] \($0.message)" }.joined(separator: "\n")
                        }())
                    }
                    .padding()

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Dynamic sandbox runtime status: Active")
                                .font(.caption)
                                .foregroundColor(.green)

                            ForEach(PreviewDiagnostics.shared.logs.filter { $0.category == "error" }) { err in
                                Text(err.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.red)
                                    .padding(8)
                                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                    .textSelection(.enabled)
                            }

                            if PreviewDiagnostics.shared.logs.filter({ $0.category == "error" }).isEmpty {
                                ContentUnavailableView("No Diagnostics Errors", systemImage: "checkmark.circle", description: Text("All diagnostics signals look normal."))
                            }
                        }
                        .padding()
                    }
                }
                .opacity(selectedSection == .diagnostics ? 1 : 0)
                .disabled(selectedSection != .diagnostics)

                // Runtime Section
                VStack(spacing: 0) {
                    HStack {
                        Label("Runtime Stream", systemImage: "play.circle")
                            .font(.headline)
                        Spacer()
                        CopyLogsButton(logs: SimulatorManager.shared.consoleLogs.joined(separator: "\n"))
                    }
                    .padding()

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(SimulatorManager.shared.consoleLogs.indices, id: \.self) { idx in
                                Text(SimulatorManager.shared.consoleLogs[idx])
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            if SimulatorManager.shared.consoleLogs.isEmpty {
                                ContentUnavailableView("No Runtime Logs", systemImage: "terminal", description: Text("Run the full application to stream simulator execution messages."))
                            }
                        }
                        .padding()
                    }
                }
                .opacity(selectedSection == .runtime ? 1 : 0)
                .disabled(selectedSection != .runtime)

                // Build Section
                VStack(spacing: 0) {
                    HStack {
                        Label("Build Console", systemImage: "hammer")
                            .font(.headline)
                        Spacer()
                        CopyLogsButton(logs: PreviewManager.shared.buildLogs.joined(separator: "\n"))
                    }
                    .padding()

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Module name: SimulationApp")
                                .font(.subheadline.bold())
                            Text(PreviewManager.shared.buildLogs.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                }
                .opacity(selectedSection == .build ? 1 : 0)
                .disabled(selectedSection != .build)

                // Environment Section
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Environment Variables", systemImage: "globe")
                            .font(.headline)

                        GroupBox("Display Modes") {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("Dark Mode", isOn: $settings.isDarkMode)
                                Toggle("Show Grid", isOn: $settings.showGrid)
                            }
                            .padding(.vertical, 4)
                        }

                        GroupBox("Device Hardware Frame") {
                            Picker("Device", selection: $settings.selectedDevice) {
                                Text("iPhone 16 Pro").tag("iPhone 16 Pro")
                                Text("iPad Pro").tag("iPad Pro")
                                Text("Apple Watch").tag("Apple Watch")
                            }
                        }
                    }
                    .padding()
                }
                .opacity(selectedSection == .environment ? 1 : 0)
                .disabled(selectedSection != .environment)

                // Logs Section
                VStack(spacing: 0) {
                    PreviewLogsView()
                }
                .opacity(selectedSection == .logs ? 1 : 0)
                .disabled(selectedSection != .logs)
            }
            .animation(.easeInOut(duration: 0.15), value: selectedSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .environment(document)
    }
}
