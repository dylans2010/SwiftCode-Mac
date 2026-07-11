import SwiftUI

/// Standard detailed workspace selector which routes the user interface depending on the sidebar selection.
public struct SimulatorDetailView: View {
    @Environment(SimulatorManager.self) private var simulatorManager
    public let selectedTab: SimulatorSidebarTab?
    public let selectedDeviceID: String?

    public var body: some View {
        Group {
            if let tab = selectedTab {
                switch tab {
                case .devices:
                    if let _ = simulatorManager.selectedDevice {
                        SimulatorDeviceInformationView()
                    } else {
                        noSelectionView(title: "No Device Selected", subtitle: "Please click on a simulator device in the sidebar.")
                    }
                case .runtimes:
                    RuntimeManagementView()
                case .deployments:
                    ApplicationDeploymentView()
                case .previews:
                    SimulatorPreviewView()
                }
            } else {
                noSelectionView(title: "Select a Category", subtitle: "Choose an item from the toolbox to begin configuration.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noSelectionView(title: String, subtitle: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "iphone.circle")
        } description: {
            Text(subtitle)
        }
    }
}
