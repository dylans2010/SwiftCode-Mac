import SwiftUI

struct SimulatorAppsView: View {
    let device: SimulatorDevice
    @State private var apps: [SimulatorApplication] = []

    // Connect to global manager
    private let manager = SimulatorManager.shared

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Installed Applications", systemImage: "app.badge")
                        .font(.headline)
                        .foregroundColor(.purple)
                    Spacer()

                    Button {
                        refreshApps()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Installed Apps")
                }

                Divider()

                if device.state != .booted {
                    ContentUnavailableView {
                        Label("Device Offline", systemImage: "iphone.slash")
                    } description: {
                        Text("Please boot this simulator device to inspect and launch installed applications.")
                    }
                    .frame(height: 180)
                } else if apps.isEmpty {
                    ContentUnavailableView {
                        Label("No Custom Apps", systemImage: "app.dashed")
                    } description: {
                        Text("Drag & drop a .app or .ipa binary bundle onto this simulator workspace to install your app.")
                    }
                    .frame(height: 180)
                } else {
                    List {
                        ForEach(apps) { app in
                            HStack {
                                Image(systemName: "app")
                                    .font(.system(size: 24))
                                    .foregroundColor(.purple)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.subheadline.bold())
                                    Text(app.bundleIdentifier)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    Button("Launch") {
                                        Task {
                                            await manager.launchApplication(bundleID: app.bundleIdentifier)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Terminate") {
                                        Task {
                                            await manager.terminateApplication(bundleID: app.bundleIdentifier)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button(role: .destructive) {
                                        Task {
                                            await manager.uninstallApplication(bundleID: app.bundleIdentifier)
                                            refreshApps()
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: 200)
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
        .onAppear {
            refreshApps()
        }
        .onChange(of: device.state) { _, _ in
            refreshApps()
        }
    }

    private func refreshApps() {
        guard device.state == .booted else {
            apps = []
            return
        }
        // Grab simulated apps list matching our device model
        apps = [
            SimulatorApplication(bundleIdentifier: "com.swiftcode.demoapp", name: "DemoApp", path: "/Users/developer/Library/Developer/CoreSimulator/Devices/\(device.udid)/data/Containers/Bundle/Application/DemoApp.app", version: "1.0.0", targetPlatform: device.platform),
            SimulatorApplication(bundleIdentifier: "com.example.swiftuipreview", name: "SwiftUI Preview Host", path: "/Users/developer/Library/Developer/CoreSimulator/Devices/\(device.udid)/data/Containers/Bundle/Application/SwiftUIHost.app", version: "2.4.1", targetPlatform: device.platform)
        ]
    }
}
