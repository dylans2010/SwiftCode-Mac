// Ported verbatim from Legacy `SwiftCode/Views/Utilities/Operations/Views/OperationsWorkspaceView.swift`
// (Dylan's own code; direct port authorised under MIT). Destination:
// swiftcode-ide — NOT SwiftCodeUI: all 16 panel views it routes to
// (`OperationsDashboardView`, `ProjectRegistryView`, `ArchiveManagerView`,
// `BuildHistoryView`, `DiagnosticsView`, `OperationsDependencyManagerView`,
// `StorageManagerView`, `OperationsSecurityCenterView`, `AIReportsView`,
// `WorkspaceHealthView`, `SCLogsView`, `SCTimelineView`, `WorkspaceSearchView`,
// `OperationQueueView`, `OperationsNotificationsView`, `PreferencesView`)
// live in swiftcode-ide as internal structs and are unreachable from
// SwiftCodeUI. `OperationsWindowController` (SwiftCodeUI :175) still
// references this type cross-target — that reference needs the panel
// views migrated into a library module, or a rebind, at wiring time.
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
                OperationsSecurityCenterView()
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
                OperationsNotificationsView()
            case .preferences:
                PreferencesView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
