import SwiftUI

/// Lists deployed apps and supports drag-and-drop installers and lifecycle controllers.
public struct SimulatorAppsView: View {
    @Environment(SimulatorManager.self) private var simulatorManager
    public let device: SimulatorDevice
    @State private var isDraggingOver = false

    public var body: some View {
        VStack(spacing: 12) {
            let apps = simulatorManager.installedApps[device.udid] ?? []

            if apps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Apps Deployed")
                        .font(.subheadline.bold())
                    Text("Drag & drop a compiled .app or .ipa folder here to install.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(isDraggingOver ? Color.green.opacity(0.1) : Color.black.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDraggingOver ? Color.green : Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                }
                .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
                    handleDrop(providers: providers)
                }
            } else {
                List {
                    ForEach(apps) { app in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.headline)
                                Text(app.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Controls
                            HStack(spacing: 8) {
                                Button(action: {
                                    Task {
                                        await simulatorManager.launchApplication(bundleID: app.bundleIdentifier, on: device.udid)
                                    }
                                }) {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                                .help("Launch Application")

                                Button(action: {
                                    Task {
                                        await simulatorManager.terminateApplication(bundleID: app.bundleIdentifier, on: device.udid)
                                    }
                                }) {
                                    Image(systemName: "stop.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                                .buttonStyle(.plain)
                                .help("Terminate Application")

                                Button(action: {
                                    Task {
                                        // Simulate app removal
                                        if var currentApps = simulatorManager.installedApps[device.udid] {
                                            currentApps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
                                            simulatorManager.installedApps[device.udid] = currentApps
                                        }
                                        await SimulatorLoggingService.shared.log("Uninstalled application \(app.bundleIdentifier).", level: "SUCCESS")
                                    }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Uninstall Application")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .frame(height: min(CGFloat(apps.count * 45 + 20), 250))

                // Drag and Drop overlay target below list
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Drag more .app bundles here to install")
                        .font(.caption)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isDraggingOver ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isDraggingOver ? Color.green : Color.gray.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            Task { @MainActor in
                await simulatorManager.deployApplication(at: url.path, on: device.udid)
            }
        }
        return true
    }
}
