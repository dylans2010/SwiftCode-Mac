import SwiftUI

@MainActor
struct SimulatorAppsView: View {
    let device: SimulatorDevice
    @State private var apps: [SimulatorApplication] = []

    private let manager = SimulatorManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
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
                                VStack(spacing: 8) {
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
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.04))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
        }
        .simulatorWorkspaceEmbedded()
        .onAppear {
            refreshApps()
        }
        .onChange(of: device.state) {
            refreshApps()
        }
    }

    private func refreshApps() {
        guard device.state == .booted else {
            apps = []
            return
        }
        apps = [
            SimulatorApplication(bundleIdentifier: "com.swiftcode.demoapp", name: "DemoApp", path: "/Users/developer/Library/Developer/CoreSimulator/Devices/\(device.udid)/data/Containers/Bundle/Application/DemoApp.app", version: "1.0.0", targetPlatform: device.platform),
            SimulatorApplication(bundleIdentifier: "com.example.swiftuipreview", name: "SwiftUI Preview Host", path: "/Users/developer/Library/Developer/CoreSimulator/Devices/\(device.udid)/data/Containers/Bundle/Application/SwiftUIHost.app", version: "2.4.1", targetPlatform: device.platform)
        ]
    }
}
