import SwiftUI

public struct VirtualizationWorkspaceView: View {
    @State private var stateStore = VirtualizationStateStore.shared

    public init() {}

    public var body: some View {
        Group {
            if stateStore.showCreateWizard {
                CreateVirtualMachineWizardView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let selectedID = stateStore.selectedVMID {
                VirtualMachineDetailView(vmID: selectedID)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            } else {
                switch stateStore.selectedSidebarTab {
                case .dashboard:
                    VirtualizationDashboardView()
                case .vmLibrary:
                    EnvironmentProfilesView()
                case .activeSessions:
                    VirtualizationDashboardView()
                case .storage:
                    VirtualMachineStorageView(vmID: stateStore.virtualMachines.first?.id)
                case .networking:
                    VirtualMachineNetworkView(vmID: stateStore.virtualMachines.first?.id)
                case .snapshots:
                    VirtualMachineSnapshotsView(vmID: stateStore.virtualMachines.first?.id)
                case .sharedFolders:
                    VirtualMachineSharedFoldersView(vmID: stateStore.virtualMachines.first?.id)
                case .displays:
                    VirtualMachineSettingsView(vmID: stateStore.virtualMachines.first?.id)
                case .devices:
                    VirtualMachineSettingsView(vmID: stateStore.virtualMachines.first?.id)
                case .console:
                    VirtualMachineConsoleView(vmID: stateStore.virtualMachines.first?.id ?? UUID())
                case .logs:
                    VirtualMachineTerminalView(vmID: stateStore.virtualMachines.first?.id ?? UUID())
                case .performance:
                    VirtualMachineMonitorView(vmID: stateStore.virtualMachines.first?.id ?? UUID())
                case .settings:
                    VirtualizationPreferencesView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: stateStore.showCreateWizard)
        .animation(.easeInOut(duration: 0.2), value: stateStore.selectedVMID)
        .animation(.easeInOut(duration: 0.2), value: stateStore.selectedSidebarTab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
