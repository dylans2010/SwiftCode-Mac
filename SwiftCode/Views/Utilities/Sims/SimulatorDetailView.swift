import SwiftUI

@MainActor
struct SimulatorDetailView: View {
    let device: SimulatorDevice

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Simulator Control Center", systemImage: "iphone")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 20) {
                    SimulatorActionsView(device: device)
                    SimulatorDeviceInformationView(device: device)
                    SimulatorAppsView(device: device)
                    SimulatorConsoleView()
                }
            }
        }
        .simulatorWorkspaceEmbedded()
    }
}
