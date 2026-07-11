import SwiftUI

/// Dedicated card workspace with full drag-and-drop targets to deploy iOS / watchOS application bundles.
public struct ApplicationDeploymentView: View {
    @Environment(SimulatorManager.self) private var simulatorManager
    @State private var targetDeviceID: String?
    @State private var isDraggingOver = false
    @State private var deploymentStatusMessage: String?
    @State private var isInstalling = false

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Banner
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("App Bundle Deployments", systemImage: "arrow.down.doc.fill")
                                .font(.title2.bold())
                                .foregroundStyle(.green)
                            Spacer()
                        }
                        Text("Install built applications and standard Apple installation files into virtual Simulator environments instantly.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Selector & Target Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("1. Choose Target Simulator", systemImage: "iphone")
                                .font(.headline)
                            Spacer()
                        }

                        let bootedDevices = simulatorManager.devices.filter { $0.state == .booted }

                        if bootedDevices.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No Booted Simulators Found")
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                Text("Please boot a simulator device using the Simulator Manager before deploying applications.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Picker("Booted Target", selection: $targetDeviceID) {
                                ForEach(bootedDevices) { device in
                                    Text(device.name).tag(device.udid as String?)
                                }
                            }
                            .pickerStyle(.menu)
                            .onAppear {
                                if targetDeviceID == nil {
                                    targetDeviceID = bootedDevices.first?.udid
                                }
                            }
                        }

                        Divider()

                        HStack {
                            Label("2. Drag & Drop App Bundle", systemImage: "square.and.arrow.down")
                                .font(.headline)
                            Spacer()
                        }

                        // Drop Area
                        VStack(spacing: 12) {
                            if isInstalling {
                                ProgressView("Installing...")
                                    .tint(.green)
                            } else {
                                Image(systemName: "app.badge.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.green)
                                Text("Drop .app or .ipa folders here")
                                    .font(.subheadline.bold())
                                Text("Deployment will target the chosen booted simulator.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(40)
                        .frame(maxWidth: .infinity)
                        .background(isDraggingOver ? Color.green.opacity(0.1) : Color.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isDraggingOver ? Color.green : Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        }
                        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
                            guard let targetUDID = targetDeviceID else {
                                deploymentStatusMessage = "Please select a booted simulator device before dropping bundles."
                                return false
                            }
                            return handleDrop(providers: providers, targetUDID: targetUDID)
                        }

                        if let message = deploymentStatusMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(message.contains("Success") ? .green : .red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
    }

    private func handleDrop(providers: [NSItemProvider], targetUDID: String) -> Bool {
        guard let provider = providers.first else { return false }
        isInstalling = true
        deploymentStatusMessage = nil

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                Task { @MainActor in
                    isInstalling = false
                    deploymentStatusMessage = "Failed to resolve file reference."
                }
                return
            }

            Task { @MainActor in
                await simulatorManager.deployApplication(at: url.path, on: targetUDID)
                isInstalling = false
                deploymentStatusMessage = "Successfully deployed application \(url.lastPathComponent) onto target simulator!"
            }
        }
        return true
    }
}
