import SwiftUI

public enum DatabaseSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case tables = "Tables & Views"
    case schemaDesigner = "Schema Designer"
    case sqlEditor = "SQL Editor"
    case migrations = "Migrations"
    case backups = "Backups"
    case importExport = "Import & Export"
    case templates = "Templates"
    case aiAssistant = "AI Assistant"
    case performance = "Performance"
    case logs = "Logs & Statistics"
    case settings = "Settings"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .tables: return "tablecells"
        case .schemaDesigner: return "point.topleft.down.to.point.bottomright.curvepath"
        case .sqlEditor: return "terminal"
        case .migrations: return "arrow.triangle.2.circlepath"
        case .backups: return "archivebox"
        case .importExport: return "arrow.up.and.down.and.arrow.left.and.right"
        case .templates: return "square.stack.3d.up"
        case .aiAssistant: return "sparkles"
        case .performance: return "gauge.with.needle"
        case .logs: return "doc.text"
        case .settings: return "gearshape"
        }
    }
}

public struct DatabaseExplorerView: View {
    @StateObject private var connManager = DatabaseConnectionManager.shared
    @State private var selectedSection: DatabaseSection = .dashboard
    @State private var showSidebar = true
    @State private var showInspector = true

    // Schema selection states
    @State private var selectedTable: DatabaseTable?
    @State private var selectedColumn: DatabaseColumn?

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Panel 1: Left Navigation Sidebar
            if showSidebar {
                DatabaseSidebar(selectedSection: $selectedSection, connManager: connManager)
                    .frame(width: 250)
                    .transition(.move(edge: .leading))

                Divider()
            }

            // Panel 2: Central Main Content Workspace
            VStack(spacing: 0) {
                // Header Toolbar
                HStack {
                    Button {
                        withAnimation { showSidebar.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Left Sidebar")

                    Text("Database Explorer")
                        .font(.headline)
                        .padding(.leading, 8)

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
                        .padding(.leading, 8)
                    }

                    Spacer()

                    Button {
                        withAnimation { showInspector.toggle() }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Right Inspector")
                }
                .padding(12)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Active workspace layout
                Group {
                    switch selectedSection {
                    case .dashboard:
                        DatabaseDashboard(selectedSection: $selectedSection)
                    case .tables:
                        DatabaseTablesView(selectedTable: $selectedTable)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Panel 3: Right Inspector Panel
            if showInspector {
                Divider()

                DatabaseInspector(selectedTable: $selectedTable, selectedColumn: $selectedColumn)
                    .frame(width: 260)
                    .transition(.move(edge: .trailing))
            }
        }
        .environmentObject(connManager)
    }
}
