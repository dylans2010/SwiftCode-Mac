import SwiftUI
import UniformTypeIdentifiers

public struct CreateVirtualMachineWizardView: View {
    @State private var stateStore = VirtualizationStateStore.shared
    @State private var step: Int = 1

    // Step 1: OS Selection
    @State private var selectedProviderName: String = "Ubuntu"
    private let providers: [any OperatingSystemProvider] = [
        UbuntuProvider(), DebianProvider(), FedoraProvider(), AlpineProvider()
    ]

    // Step 2: Select Image
    @State private var selectedImageID: UUID? = nil
    @State private var customImagePath: String = ""

    // Step 3: Configure Resources
    @State private var cpuCores: Double = 4
    @State private var memoryGB: Double = 8
    @State private var storageGB: Double = 64

    // Step 4: Configure Features
    @State private var shareFolders: Bool = true
    @State private var clipboardSharing: Bool = true
    @State private var networkAccess: Bool = true
    @State private var portForwarding: Bool = true
    @State private var terminalAccess: Bool = true
    @State private var automaticSnapshots: Bool = false

    // VM general
    @State private var vmName: String = ""

    public init() {}

    private var activeProvider: any OperatingSystemProvider {
        providers.first { $0.name == selectedProviderName } ?? UbuntuProvider()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wizard Title Banner
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Virtual Machine Creation Wizard")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Step \(step) of 5 • \(stepName(step))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    stateStore.showCreateWizard = false
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Step Body Workspace
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 1:
                        stepOneView()
                    case 2:
                        stepTwoView()
                    case 3:
                        stepThreeView()
                    case 4:
                        stepFourView()
                    case 5:
                        stepFiveView()
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }

            Divider()

            // Bottom Action buttons
            HStack {
                if step > 1 {
                    Button("Back") {
                        step -= 1
                    }
                    .controlSize(.large)
                }
                Spacer()

                Button("Cancel") {
                    stateStore.showCreateWizard = false
                }
                .controlSize(.large)

                if step < 5 {
                    Button("Continue") {
                        if step == 1 {
                            // Preset defaults based on recommended OS choices
                            let recommended = activeProvider
                            cpuCores = Double(recommended.recommendedCores)
                            memoryGB = Double(recommended.recommendedMemoryMB) / 1024.0
                            storageGB = Double(recommended.recommendedStorageGB)
                            if vmName.isEmpty {
                                vmName = "\(recommended.name) Server Development"
                            }
                        }
                        step += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Create VM") {
                        createVM()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func stepName(_ step: Int) -> String {
        switch step {
        case 1: return "Choose Operating System Provider"
        case 2: return "Select Image File"
        case 3: return "Configure CPU, RAM & Disk Storage"
        case 4: return "Configure Development Features"
        case 5: return "Review and Finalize"
        default: return ""
        }
    }

    @ViewBuilder
    private func stepOneView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Select an operating system provider to deploy. We optimize resource structures based on your choices.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(providers, id: \.name) { prov in
                Button {
                    selectedProviderName = prov.name
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: selectedProviderName == prov.name ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedProviderName == prov.name ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(prov.name)
                                .font(.headline)
                            Text(prov.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Recommended specs: CPU: \(prov.recommendedCPU) • RAM: \(prov.recommendedRAM) • Disk: \(prov.recommendedStorage)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedProviderName == prov.name ? Color.blue : Color.primary.opacity(0.1), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func stepTwoView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Virtual Machine Image Picker")
                .font(.headline)
            Text("Select an existing ISO file or specify a download link.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Official download source for \(activeProvider.name):")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Provide download pages from the official distribution website. Never download unknown binary images.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(activeProvider.officialDownloadPage)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.blue)
                        Spacer()
                        Button("Open Download Page") {
                            if let url = URL(string: activeProvider.officialDownloadPage) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(6)
                }
                .padding(.vertical, 4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            GroupBox(label: Text("Local Image Path").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Path to local ISO/IMG file...", text: $customImagePath)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Select local file...") {
                            let openPanel = NSOpenPanel()
                            openPanel.allowsMultipleSelection = false
                            openPanel.canChooseDirectories = false
                            openPanel.canChooseFiles = true
                            var types: [UTType] = [.diskImage]
                            if let isoType = UTType(filenameExtension: "iso") {
                                types.append(isoType)
                            }
                            openPanel.allowedContentTypes = types
                            if openPanel.runModal() == .OK, let url = openPanel.url {
                                customImagePath = url.path
                            }
                        }
                        Spacer()
                        Text("Supported formats: \(activeProvider.supportedImageFormats.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    @ViewBuilder
    private func stepThreeView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hardware Resource Allocations")
                .font(.headline)
            Text("Allocate host computer resources to the virtual environment. Ensure you leave enough resource capability for macOS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("CPU Cores:")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(cpuCores)) Cores")
                            .fontWeight(.bold)
                    }
                    Slider(value: $cpuCores, in: 1...16, step: 1)
                    Text("Recommended for \(activeProvider.name): \(activeProvider.recommendedCores) Cores")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 4)

                    HStack {
                        Text("Memory (RAM):")
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.1f GB", memoryGB))
                            .fontWeight(.bold)
                    }
                    Slider(value: $memoryGB, in: 1...64, step: 0.5)
                    Text("Recommended for \(activeProvider.name): \(activeProvider.recommendedMemoryMB / 1024) GB")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 4)

                    HStack {
                        Text("Virtual Hard Disk Size:")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(storageGB)) GB")
                            .fontWeight(.bold)
                    }
                    Slider(value: $storageGB, in: 10...1000, step: 5)
                    Text("Recommended for \(activeProvider.name): \(activeProvider.recommendedStorageGB) GB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    @ViewBuilder
    private func stepFourView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Development Features Configuration")
                .font(.headline)
            Text("Enable native integration features designed for IDE software workspaces.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $shareFolders) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shared Project Folders")
                                .fontWeight(.medium)
                            Text("Mount active SwiftCode project directory into guest VM at /mnt/workspace automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Divider()

                    Toggle(isOn: $clipboardSharing) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bidirectional Clipboard Sharing")
                                .fontWeight(.medium)
                            Text("Copy and paste text seamlessly between host macOS and guest VM.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Divider()

                    Toggle(isOn: $networkAccess) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Network NAT Access")
                                .fontWeight(.medium)
                            Text("Grant internet and local LAN access inside the environment.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Divider()

                    Toggle(isOn: $portForwarding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto Port Forwarding")
                                .fontWeight(.medium)
                            Text("Automatically map standard developer web ports (e.g. 3000, 8080) to localhost.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .padding(.vertical, 4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    @ViewBuilder
    private func stepFiveView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review and Finalize Environment")
                .font(.headline)
            Text("Ensure all configured specifications are accurate before allocating disk structures.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Environment Name:")
                            .fontWeight(.medium)
                        Spacer()
                        TextField("Name your environment...", text: $vmName)
                            .frame(width: 250)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    HStack {
                        Text("Operating System:")
                        Spacer()
                        Text(activeProvider.name)
                            .fontWeight(.bold)
                    }

                    HStack {
                        Text("Image Location:")
                        Spacer()
                        Text(customImagePath.isEmpty ? "None Selected (Use recommended OS download)" : customImagePath)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack {
                        Text("Processor Allocation:")
                        Spacer()
                        Text("\(Int(cpuCores)) Cores")
                    }

                    HStack {
                        Text("RAM Allocated:")
                        Spacer()
                        Text(String(format: "%.1f GB", memoryGB))
                    }

                    HStack {
                        Text("Hard Disk Storage:")
                        Spacer()
                        Text("\(Int(storageGB)) GB")
                    }
                }
                .padding(.vertical, 4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    private func createVM() {
        let ramMB = Int(memoryGB * 1024)
        let _ = stateStore.createVM(
            name: vmName.isEmpty ? "\(selectedProviderName) Environment" : vmName,
            osType: selectedProviderName,
            version: activeProvider.versions.first ?? "Custom",
            cpu: Int(cpuCores),
            ramMB: ramMB,
            diskGB: Int(storageGB),
            imagePath: customImagePath.isEmpty ? nil : customImagePath
        )
        stateStore.showCreateWizard = false
    }
}
