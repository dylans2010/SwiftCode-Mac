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

/// Main entry point for the Database Explorer.
/// Optimizes and routes the workspace to a native macOS AppKit split-view window.
public struct DatabaseExplorerView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Database Explorer Workspace")
                .font(.title)
                .bold()

            Text("The database workspace is optimized as a native macOS AppKit split-view layout with direct SQLite3 connection mappings, PostgREST API synchronizers, and AI assistant query consoles.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: openWorkspace) {
                Label("Launch Workspace", systemImage: "arrow.up.forward.app")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            openWorkspace()
        }
    }

    private func openWorkspace() {
        DatabaseExplorerWindowManager.shared.showWindow()
        dismiss()
    }
}
