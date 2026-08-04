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
                    Text("• CPU: \(provider.recommendedCPU)")
                    Text("• Memory (RAM): \(provider.recommendedRAM)")
                    Text("• Storage: \(provider.recommendedStorage)")
                    Text("• Supported Architectures: \(provider.supportedArchitectures)")
                }
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Installation Notes:")
                        .fontWeight(.bold)
                    Text(provider.installationNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Open Official Download Link") {
                        if let url = URL(string: provider.officialDownloadPage) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Documentation") {
                        if let url = URL(string: provider.officialDocumentation) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Website") {
                        if let url = URL(string: provider.officialWebsite) {
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
