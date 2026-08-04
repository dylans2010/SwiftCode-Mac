import SwiftUI

public struct OperatingSystemProviderView: View {
    public let provider: any OperatingSystemProvider

    public init(provider: any OperatingSystemProvider) {
        self.provider = provider
    }

    public var body: some View {
        GroupBox(label: Text(provider.name).font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(provider.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommended Resources:")
                        .fontWeight(.bold)
                    Text("• CPU Cores: \(provider.recommendedCores) Cores")
                    Text("• Memory: \(provider.recommendedMemoryMB / 1024) GB")
                    Text("• Disk Storage: \(provider.recommendedStorageGB) GB")
                }
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Installation Instructions:")
                        .fontWeight(.bold)
                    Text(provider.installationInstructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Open Official Download Link") {
                        if let url = URL(string: provider.downloadSource) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Documentation") {
                        if let url = URL(string: provider.documentationLink) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }
}
