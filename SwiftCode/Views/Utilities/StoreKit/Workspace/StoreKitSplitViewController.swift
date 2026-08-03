import AppKit
import SwiftUI

@MainActor
public class StoreKitSplitViewController: NSSplitViewController {
    private var leftItem: NSSplitViewItem?
    private var centerItem: NSSplitViewItem?
    private var rightItem: NSSplitViewItem?

    public let session: StoreKitWorkspaceSession

    public init(session: StoreKitWorkspaceSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        // 1. Left Sidebar
        let leftSidebarView = StoreKitSidebarView().environment(session)
        let leftVC = NSHostingController(rootView: leftSidebarView)
        leftVC.view.autoresizingMask = [.width, .height]
        let leftItem = NSSplitViewItem(sidebarWithViewController: leftVC)
        leftItem.canCollapse = true
        leftItem.minimumThickness = 230
        leftItem.maximumThickness = 320
        leftItem.holdingPriority = .defaultLow + 10
        self.leftItem = leftItem
        addSplitViewItem(leftItem)

        // 2. Center Workspace Editor
        let centerWorkspaceView = StoreKitCenterWorkspaceView().environment(session)
        let centerVC = NSHostingController(rootView: centerWorkspaceView)
        centerVC.sizingOptions = []
        centerVC.view.autoresizingMask = [.width, .height]
        let centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.minimumThickness = 550
        centerItem.holdingPriority = .defaultLow - 10
        self.centerItem = centerItem
        addSplitViewItem(centerItem)

        // 3. Right Properties Inspector
        let rightInspectorView = StoreKitInspectorView().environment(session)
        let rightVC = NSHostingController(rootView: rightInspectorView)
        rightVC.sizingOptions = []
        rightVC.view.autoresizingMask = [.width, .height]
        let rightItem = NSSplitViewItem(viewController: rightVC)
        rightItem.canCollapse = true
        rightItem.minimumThickness = 250
        rightItem.maximumThickness = 320
        rightItem.holdingPriority = .defaultLow + 20
        self.rightItem = rightItem
        addSplitViewItem(rightItem)

        // Restore split configurations or defaults
        restoreLayoutStates()
    }

    public func toggleLeftSidebar(_ sender: Any?) {
        leftItem?.isCollapsed.toggle()
        saveLayoutStates()
    }

    public func toggleRightInspector(_ sender: Any?) {
        rightItem?.isCollapsed.toggle()
        saveLayoutStates()
    }

    private func saveLayoutStates() {
        UserDefaults.standard.set(leftItem?.isCollapsed ?? false, forKey: "com.swiftcode.storekit.leftSidebarCollapsed")
        UserDefaults.standard.set(rightItem?.isCollapsed ?? false, forKey: "com.swiftcode.storekit.rightInspectorCollapsed")
    }

    private func restoreLayoutStates() {
        let leftCollapsed = UserDefaults.standard.bool(forKey: "com.swiftcode.storekit.leftSidebarCollapsed")
        let rightCollapsed = UserDefaults.standard.bool(forKey: "com.swiftcode.storekit.rightInspectorCollapsed")
        leftItem?.isCollapsed = leftCollapsed
        rightItem?.isCollapsed = rightCollapsed
    }
}

// Wrapper for center panel managing editor routing based on Session's selection state
struct StoreKitCenterWorkspaceView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var simulationService = StoreKitSimulationService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Workspace Status Indicator Bar / Breadcrumb Navigation
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .foregroundColor(.accentColor)
                Text("StoreKit Workspace")
                    .font(.caption.bold())
                Text("/")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(session.selectedSection)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let fileURL = session.activeURL {
                    Spacer()
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                    Text(fileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Spacer()
                    Text("In-Memory Temporary Config")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }

                // Error Diagnostics Indicator Badge
                let issuesCount = StoreKitValidationService.shared.validate(config: session.activeConfig).count
                if issuesCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(issuesCount) Issues")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("No Issues")
                    }
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            Group {
                switch session.selectedSection {
                case "Dashboard":
                    StoreKitDashboardView()
                case "Products":
                    StoreKitProductsView()
                case "Consumables", "Non Consumables", "Auto Renewables", "Non Renewables":
                    StoreKitProductsView(filterType: session.selectedSection)
                case "Subscription Groups":
                    StoreKitSubscriptionGroupEditorView()
                case "Offers":
                    StoreKitOfferEditorView()
                case "Storefronts":
                    StoreKitStorefrontEditorView()
                case "Localization":
                    StoreKitLocalizationEditorView()
                case "Assets":
                    StoreKitAssetEditorView()
                case "Purchase Simulator":
                    StoreKitPurchaseSimulatorView()
                case "Transactions":
                    StoreKitTransactionExplorerView()
                case "Diagnostics", "Validation":
                    StoreKitDiagnosticsView()
                case "Templates":
                    StoreKitTemplateGalleryView()
                case "Logs":
                    StoreKitLogsView()
                case "Settings":
                    StoreKitSettingsView()
                case "Raw Source":
                    StoreKitRawSourceEditorView()
                default:
                    StoreKitDashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
