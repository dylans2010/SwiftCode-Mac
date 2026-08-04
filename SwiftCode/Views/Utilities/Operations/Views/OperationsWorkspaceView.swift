import SwiftUI

struct OperationsWorkspaceView: View {
    @State private var coord = OperationsCoordinator.shared

    var body: some View {
        VStack(spacing: 0) {
            // Main Panel Routing
            switch coord.selectedPanel {
            case .dashboard:
                OperationsDashboardView()
            case .projectRegistry:
                ProjectRegistryView()
            case .archives:
                ArchiveManagerView()
            case .buildHistory:
                BuildHistoryView()
            case .diagnostics:
                DiagnosticsView()
            case .dependencies:
                OperationsDependencyManagerView()
            case .storage:
                StorageManagerView()
            case .security:
                SecurityCenterView()
            case .aiReports:
                AIReportsView()
            case .health:
                WorkspaceHealthView()
            case .logs:
                SCLogsView()
            case .timeline:
                SCTimelineView()
            case .search:
                WorkspaceSearchView()
            case .queue:
                OperationQueueView()
            case .notifications:
                NotificationsView()
            case .preferences:
                PreferencesView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
