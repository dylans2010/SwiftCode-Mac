import SwiftUI

public struct VirtualizationWorkspaceView: View {
    @State private var stateStore = VirtualizationStateStore.shared

    public init() {}

    public var body: some View {
        Group {
            if stateStore.showCreateWizard {
                CreateVirtualMachineWizardView()
            } else if let selectedID = stateStore.selectedVMID {
                VirtualMachineDetailView(vmID: selectedID)
            } else {
                switch stateStore.selectedSidebarTab {
                case .dashboard:
                    VirtualizationDashboardView()
                case .environments:
                    EnvironmentProfilesView()
                case .images:
                    VirtualizationImageBrowserView()
                case .snapshots:
                    // General snapshot list or settings
                    VirtualMachineSnapshotsView(vmID: stateStore.virtualMachines.first?.id)
                case .storage:
                    VirtualMachineStorageView(vmID: stateStore.virtualMachines.first?.id)
                case .networking:
                    VirtualMachineNetworkView(vmID: stateStore.virtualMachines.first?.id)
                case .settings:
                    VirtualizationPreferencesView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
