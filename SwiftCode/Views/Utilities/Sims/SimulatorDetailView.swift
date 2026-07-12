import SwiftUI

struct SimulatorDetailView: View {
    let device: SimulatorDevice

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Actions card
                SimulatorActionsView(device: device)

                // Specifications card
                SimulatorDeviceInformationView(device: device)

                // Installed Apps card
                SimulatorAppsView(device: device)

                // Console logging card
                SimulatorConsoleView()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
}
