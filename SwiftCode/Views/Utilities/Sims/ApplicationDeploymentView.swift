import SwiftUI

@MainActor
struct ApplicationDeploymentView: View {
    @State private var manager = SimulatorManager.shared
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("App Deployment & Drag-Drop", systemImage: "square.and.arrow.down.fill")
                    .font(.headline)
                    .foregroundColor(.indigo)
                Spacer()
            }
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox {
                        VStack(spacing: 16) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 40))
                                .foregroundColor(isTargeted ? .accentColor : .secondary)

                            VStack(spacing: 4) {
                                Text("Drag & Drop App Bundle Here")
                                    .font(.headline)
                                Text("Accepts compiled iOS .app packages or .ipa archives")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let selected = manager.selectedDevice {
                                Text("Target Device: \(selected.name) (\(selected.state.rawValue))")
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(6)
                            } else {
                                Text("Please select a device in the sidebar first.")
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                                .background(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                        )
                        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                            guard let provider = providers.first else { return false }

                            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                if let url = url {
                                    Task { @MainActor in
                                        await manager.installApplication(at: url)
                                    }
                                }
                            }
                            return true
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
        }
        .simulatorWorkspaceEmbedded()
    }
}
