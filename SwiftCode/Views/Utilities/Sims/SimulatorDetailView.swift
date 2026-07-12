import SwiftUI

struct SimulatorDetailView: View {
    let device: SimulatorDevice

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Actions card
                SimulatorActionsView(device: device)

                // Specifications card
                SimulatorDeviceInformationView(device: device)

                // Installed Apps card
                SimulatorAppsView(device: device)

                // Console logging card
                SimulatorConsoleView()
            }
            .padding(24)
        }
    }
}
