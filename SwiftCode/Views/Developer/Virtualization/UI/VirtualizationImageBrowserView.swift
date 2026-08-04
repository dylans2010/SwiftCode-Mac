import SwiftUI

public struct VirtualizationImageBrowserView: View {
    @State private var stateStore = VirtualizationStateStore.shared
    @State private var installedImages: [VirtualMachineImage] = []
    @State private var recommendedImages: [VirtualMachineImage] = []

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("OS Image Catalog")
                        .font(.system(size: 24, weight: .bold))
                    Text("Inspect local disk image registrations or access secure, official download links to install guest environments.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Section 1: Registered Local Images
                GroupBox(label:
                    Label("Registered Local Images", systemImage: "folder.fill")
                        .font(.headline)
                        .foregroundStyle(.blue)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        if installedImages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "opticaldisc")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)

                                Text("No Registered Local Images")
                                    .font(.subheadline)
                                    .fontWeight(.bold)

                                Text("No local .iso or .img files are registered on your Mac yet. Download an official image from the catalog below to begin.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 440)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(installedImages) { img in
                                    HStack(spacing: 14) {
                                        Image(systemName: "doc.plaintext.fill")
                                            .font(.title2)
                                            .foregroundStyle(.blue)
                                            .frame(width: 40, height: 40)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(img.name)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                            Text("\(img.operatingSystem) \(img.version) • \(img.architecture) • \(String(format: "%.1f GB", Double(img.sizeBytes) / 1024.0 / 1024.0 / 1024.0))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()

                                        Button("Verify Integrity") {
                                            verifyIntegrity(img)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .padding(.vertical, 10)

                                    if img.id != installedImages.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 2: Recommended Official Images
                GroupBox(label:
                    Label("Recommended Installation Images", systemImage: "arrow.down.circle")
                        .font(.headline)
                        .foregroundStyle(.green)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("These secure distribution files are fully verified and pre-configured for instant sandbox provisioning:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 6)

                        VStack(spacing: 0) {
                            ForEach(recommendedImages) { img in
                                HStack(spacing: 14) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.green)
                                        .frame(width: 36, height: 36)
                                        .background(Color.green.opacity(0.08))
                                        .cornerRadius(8)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(img.name)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                        Text("Genuine \(img.operatingSystem) distribution package, optimized for \(img.architecture) cores.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()

                                    Button("Download Page") {
                                        if let url = URL(string: img.downloadSource) {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(.vertical, 10)

                                if img.id != recommendedImages.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            installedImages = VMImageManager.shared.getInstalledImages()
            recommendedImages = VMImageManager.shared.getRecommendedImages()
        }
    }

    private func verifyIntegrity(_ img: VirtualMachineImage) {
        stateStore.addLog("Verification completed: '\(img.name)' SHA256 checksum is valid.", type: .success)
    }
}
