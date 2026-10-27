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
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .liquidGlass(style: .subtle, cornerRadius: 0)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    SimulatorActionsView(device: device)
                    SimulatorDeviceInformationView(device: device)
                    SimulatorAppsView(device: device)
                    SimulatorConsoleView()
                }
                .padding(16)
            }
        }
    }
}
