import SwiftUI

/// Modern card-based catalog to inspect, download, and manage system Platform SDK runtimes.
public struct RuntimeManagementView: View {
    @Environment(SimulatorManager.self) private var simulatorManager

    // Sample list of available downloadable platforms
    private let availablePlatforms = [
        DownloadablePlatform(name: "iOS 18.2 SDK", version: "18.2", size: "7.4 GB", status: "Installed"),
        DownloadablePlatform(name: "iOS 17.5 SDK", version: "17.5", size: "6.8 GB", status: "Installed"),
        DownloadablePlatform(name: "watchOS 11.2 SDK", version: "11.2", size: "3.2 GB", status: "Downloadable"),
        DownloadablePlatform(name: "visionOS 2.2 SDK", version: "2.2", size: "8.1 GB", status: "Downloadable"),
        DownloadablePlatform(name: "tvOS 18.2 SDK", version: "18.2", size: "2.8 GB", status: "Downloadable")
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Main Header Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Xcode Platform SDKs", systemImage: "cpu.fill")
                                .font(.title2.bold())
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        Text("Manage system platforms for compilation and simulation. Installing newer platforms expands available target devices.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Downloadable SDKs grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)], spacing: 16) {
                    ForEach(availablePlatforms) { platform in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: platform.status == "Installed" ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(platform.status == "Installed" ? .green : .blue)
                                Spacer()
                                Text(platform.size)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(platform.name)
                                    .font(.headline)
                                Text("Version \(platform.version)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            HStack {
                                Text(platform.status)
                                    .font(.caption2.bold())
                                    .foregroundStyle(platform.status == "Installed" ? .green : .blue)
                                Spacer()
                                if platform.status != "Installed" {
                                    Button("Download") {
                                        // Simulate background downloading trigger
                                        Task {
                                            await SimulatorLoggingService.shared.log("Downloading Platform SDK for \(platform.name)...", level: "INFO")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Text("System Default")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct DownloadablePlatform: Identifiable, Sendable, Hashable {
    let id = UUID()
    let name: String
    let version: String
    let size: String
    let status: String
}
