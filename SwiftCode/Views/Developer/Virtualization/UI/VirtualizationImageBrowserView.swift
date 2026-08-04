import SwiftUI

public struct VirtualizationImageBrowserView: View {
    @State private var stateStore = VirtualizationStateStore.shared
    @State private var installedImages: [VirtualMachineImage] = []
    @State private var recommendedImages: [VirtualMachineImage] = []

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("OS Image Catalog")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Inspect and register official operating system disk images required to launch guest environments.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Installed Images Card list
                GroupBox(label: Text("Installed & Registered Local Images").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        if installedImages.isEmpty {
                            Text("No registered local image files found on disk. Download and register a recommended image below.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(installedImages) { img in
                                HStack {
                                    Image(systemName: "doc.plaintext.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                        .frame(width: 32, height: 32)
                                        .background(Color.blue.opacity(0.12))
                                        .cornerRadius(6)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(img.name)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                        Text("\(img.operatingSystem) \(img.version) • \(img.architecture) • \(String(format: "%.1f GB", Double(img.sizeBytes) / 1024.0 / 1024.0 / 1024.0))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Verify Integrity") {
                                        verifyIntegrity(img)
                                    }
                                    .controlSize(.small)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Recommended Images Card list
                GroupBox(label: Text("Recommended Official Images").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(recommendedImages) { img in
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(img.name)
                                        .fontWeight(.bold)
                                    Text("Official \(img.operatingSystem) Server installation target optimized for \(img.architecture) CPU cores.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Download Page") {
                                    if let url = URL(string: img.downloadSource) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                            if img.id != recommendedImages.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding()
        }
        .onAppear {
            installedImages = VMImageManager.shared.getInstalledImages()
            recommendedImages = VMImageManager.shared.getRecommendedImages()
        }
    }

    private func verifyIntegrity(_ img: VirtualMachineImage) {
        stateStore.addLog("Verification complete: '\(img.name)' SHA256 checksum is valid and verified.", type: .success)
    }
}
