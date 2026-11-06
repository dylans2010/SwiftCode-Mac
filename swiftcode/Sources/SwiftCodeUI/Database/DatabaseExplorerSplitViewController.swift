import AppKit
import SwiftUI
import SwiftCodeCloud

/// The Database Explorer's three-pane workspace: source-list
/// sidebar (left), section content (center), properties inspector
/// (right).
///
/// Ported from Legacy's
/// `Views/Utilities/Database/DatabaseExplorerSplitViewController.swift`.
/// The AppKit shell — the split items, their sizes and collapse
/// behaviour, the toggle actions, and the two shared-state bridges
/// (`DatabaseSplitViewState`, `DatabaseObservableState`) — is
/// verbatim Legacy and fully real.
///
/// KNOWN FORWARD DEPENDENCY (not a placeholder): the center and
/// inspector panes host SwiftUI views from Legacy's `Views/`
/// family — `DatabaseSidebar`, `DatabaseDashboard`,
/// `DatabaseTablesView`, `DatabaseSchemaView`, `DatabaseQueryEditor`,
/// `DatabaseMigrationView`, `DatabaseBackupView`,
/// `DatabaseImportExportView`, `DatabaseTemplatesView`,
/// `DatabaseAIView`, `DatabasePerformanceView`, `DatabaseLogsView`,
/// `DatabaseSettingsView`, and `DatabaseInspector` — none of which
/// exists in this destination yet (they belong to the Views family,
/// not to this Core/Helpers/Controllers family). This file is
/// staged as-is and compiles once that family lands; the view
/// names are referenced, never stubbed or redeclared here. Two of
/// those names need care when the Views family is ported:
/// `DatabaseDashboard` (SwiftUI view) collides by name with the
/// `DatabaseDashboard` class already in
/// `SwiftCodeIDECore/Model/Database/DatabaseDashboard.swift` — the
/// Views port must qualify or rename it — and the eight sections
/// the SQLite Explorer's `SQLiteExplorerSectionsController` already
/// renders (dashboard, migrations, backups, import/export,
/// templates, AI, performance, logs) must not be re-implemented a
/// second time in the Views family.
@MainActor
public class DatabaseExplorerSplitViewController: NSSplitViewController {
    private var leftItem: NSSplitViewItem?
    private var centerItem: NSSplitViewItem?
    private var rightItem: NSSplitViewItem?

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        // 1. Left Sidebar Panel (Native AppKit Outline View Controller)
        let leftVC = DatabaseExplorerSidebarViewController()
        let leftItem = NSSplitViewItem(sidebarWithViewController: leftVC)
        leftItem.canCollapse = true
        leftItem.minimumThickness = 240
        leftItem.maximumThickness = 320
        leftItem.holdingPriority = .defaultLow + 10
        self.leftItem = leftItem
        addSplitViewItem(leftItem)

        // 2. Center Workspace (Tables lists, schema viewer, SQL editors, performance logs)
        let centerVC = NSHostingController(rootView: DatabaseExplorerCenterWrapper())
        centerVC.sizingOptions = []
        centerVC.view.autoresizingMask = [.width, .height]
        let centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.minimumThickness = 500
        centerItem.holdingPriority = .defaultLow - 10
        self.centerItem = centerItem
        addSplitViewItem(centerItem)

        // 3. Right properties inspector
        let rightVC = NSHostingController(rootView: DatabaseExplorerInspectorWrapper())
        rightVC.sizingOptions = []
        rightVC.view.autoresizingMask = [.width, .height]
        let rightItem = NSSplitViewItem(viewController: rightVC)
        rightItem.canCollapse = true
        rightItem.minimumThickness = 260
        rightItem.maximumThickness = 320
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

// Global shared state bridges to make wrappers cleanly compile
@MainActor
final class DatabaseSplitViewState {
    static let shared = DatabaseSplitViewState()
    var selectedSection: DatabaseSection = .dashboard
    var selectedTable: DatabaseTable? = nil
    var selectedColumn: DatabaseColumn? = nil
    private init() {}
}

@Observable
@MainActor
final class DatabaseObservableState {
    static let shared = DatabaseObservableState()
    var selectedSection: DatabaseSection = .dashboard
    var selectedTable: DatabaseTable? = nil
    var selectedColumn: DatabaseColumn? = nil
    private init() {}
}

struct DatabaseExplorerSidebarWrapper: View {
    @State private var observableState = DatabaseObservableState.shared
    @StateObject private var connManager = DatabaseConnectionManager.shared

    var body: some View {
        DatabaseSidebar(
            selectedSection: Binding(
                get: { observableState.selectedSection },
                set: { observableState.selectedSection = $0; DatabaseSplitViewState.shared.selectedSection = $0 }
            ),
            connManager: connManager
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .environmentObject(connManager)
    }
}

struct DatabaseExplorerCenterWrapper: View {
    @State private var observableState = DatabaseObservableState.shared
    @StateObject private var connManager = DatabaseConnectionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 16) {
                Text("Database Explorer")
                    .font(.headline)

                if let active = connManager.activeConnection {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(active.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Spacer()

                // Native segmented control reducing sidebar reliance
                Picker("Workspace Panel", selection: Binding(
                    get: { observableState.selectedSection },
                    set: { observableState.selectedSection = $0; DatabaseSplitViewState.shared.selectedSection = $0 }
                )) {
                    Text("Dashboard").tag(DatabaseSection.dashboard)
                    Text("Tables").tag(DatabaseSection.tables)
                    Text("Designer").tag(DatabaseSection.schemaDesigner)
                    Text("SQL").tag(DatabaseSection.sqlEditor)
                    Text("AI").tag(DatabaseSection.aiAssistant)
                    Text("Templates").tag(DatabaseSection.templates)
                    Text("Logs").tag(DatabaseSection.logs)
                    Text("Settings").tag(DatabaseSection.settings)
                }
                .pickerStyle(.segmented)
                .frame(width: 580)

                Spacer()
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            Group {
                switch observableState.selectedSection {
                case .dashboard:
                    DatabaseDashboard(selectedSection: Binding(
                        get: { observableState.selectedSection },
                        set: { observableState.selectedSection = $0; DatabaseSplitViewState.shared.selectedSection = $0 }
                    ))
                case .tables:
                    DatabaseTablesView(selectedTable: Binding(
                        get: { observableState.selectedTable },
                        set: { observableState.selectedTable = $0; DatabaseSplitViewState.shared.selectedTable = $0 }
                    ))
                case .schemaDesigner:
                    DatabaseSchemaView()
                case .sqlEditor:
                    DatabaseQueryEditor()
                case .migrations:
                    DatabaseMigrationView()
                case .backups:
                    DatabaseBackupView()
                case .importExport:
                    DatabaseImportExportView()
                case .templates:
                    DatabaseTemplatesView()
                case .aiAssistant:
                    DatabaseAIView()
                case .performance:
                    DatabasePerformanceView()
                case .logs:
                    DatabaseLogsView()
                case .settings:
                    DatabaseSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environmentObject(connManager)
    }
}

struct DatabaseExplorerInspectorWrapper: View {
    @State private var observableState = DatabaseObservableState.shared

    var body: some View {
        DatabaseInspector(
            selectedTable: Binding(
                get: { observableState.selectedTable },
                set: { observableState.selectedTable = $0; DatabaseSplitViewState.shared.selectedTable = $0 }
            ),
            selectedColumn: Binding(
                get: { observableState.selectedColumn },
                set: { observableState.selectedColumn = $0; DatabaseSplitViewState.shared.selectedColumn = $0 }
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
