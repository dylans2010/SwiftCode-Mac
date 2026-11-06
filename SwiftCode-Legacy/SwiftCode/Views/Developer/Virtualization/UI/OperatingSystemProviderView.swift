import SwiftUI

public struct OperatingSystemProviderView: View {
    public let provider: any OperatingSystemProvider

    public init(provider: any OperatingSystemProvider) {
        self.provider = provider
    }

    public var body: some View {
        GroupBox(label:
            HStack(spacing: 8) {
                Image(systemName: provSystemIcon(provider.name))
                    .font(.title2)
                    .foregroundStyle(provColor(provider.name))

                Text(provider.name)
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                Text("Official Distribution")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .cornerRadius(4)
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(provider.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                // Resource specifications grid
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Sizing & Recommendations:")
                        .fontWeight(.bold)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        SCDetailRow(label: "Processor Cores", value: provider.recommendedCPU)
                        SCDetailRow(label: "Memory (RAM)", value: provider.recommendedRAM)
                        SCDetailRow(label: "Disk Storage", value: provider.recommendedStorage)
                        SCDetailRow(label: "Architectures", value: provider.supportedArchitectures)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Provisioning & Deployment Notes:")
                        .fontWeight(.bold)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(provider.installationNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(6)
                }

                // Official Action links
                HStack(spacing: 12) {
                    Button {
                        if let url = URL(string: provider.officialDownloadPage) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Download Images", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        if let url = URL(string: provider.officialDocumentation) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Documentation", systemImage: "doc.text.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let url = URL(string: provider.officialWebsite) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Website", systemImage: "safari.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func provSystemIcon(_ name: String) -> String {
        switch name {
        case "Ubuntu": return "cpu"
        case "Debian": return "circle.circle"
        case "Fedora": return "shippingbox"
        case "Alpine": return "snowflake"
        default: return "terminal"
        }
    }

    private func provColor(_ name: String) -> Color {
        switch name {
        case "Ubuntu": return .orange
        case "Debian": return .red
        case "Fedora": return .blue
        case "Alpine": return .teal
        default: return .secondary
        }
    }
}
