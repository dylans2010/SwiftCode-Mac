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

    // Step 1.5: Template Selection
    @State private var selectedTemplateID: String = "blank"

    // Step 2: Select Image
    @State private var selectedImageID: UUID? = nil
    @State private var customImagePath: String = ""

    // Step 3: Configure Resources (Calculated dynamically)
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

    private var activeTemplate: VirtualizationStateStore.QuickStartTemplate {
        stateStore.quickStartTemplates.first { $0.id == selectedTemplateID } ?? stateStore.quickStartTemplates.last!
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wizard Title Banner
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Virtual Machine Creation Wizard")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Step \(step) of 6 • \(stepName(step))")
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
                        stepOnePointFiveView()
                    case 3:
                        stepTwoView()
                    case 4:
                        stepThreeView()
                    case 5:
                        stepFourView()
                    case 6:
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

                if step < 6 {
                    Button("Continue") {
                        if step == 1 {
                            // Seed template recommendations early
                            applySmartRecommendations()
                        } else if step == 2 {
                            // Seed template settings and auto-name
                            applySmartRecommendations()
                            if vmName.isEmpty {
                                vmName = "\(activeProvider.name) \(activeTemplate.name)"
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
        case 2: return "Select Environment Template Preset (Quick Start)"
        case 3: return "Select Image File"
        case 4: return "Configure CPU, RAM & Disk Storage (Recommended)"
        case 5: return "Configure Development Features"
        case 6: return "Review and Finalize"
        default: return ""
        }
    }

    private func applySmartRecommendations() {
        let recs = stateStore.getSmartRecommendation(osType: selectedProviderName, templateID: selectedTemplateID)
        cpuCores = Double(recs.cores)
        memoryGB = Double(recs.memoryMB) / 1024.0
        storageGB = Double(recs.storageGB)
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
    private func stepOnePointFiveView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Select a development preset template. This pre-configures hardware recommendations, required tools, and development settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(stateStore.quickStartTemplates) { template in
                        Button {
                            selectedTemplateID = template.id
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: selectedTemplateID == template.id ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedTemplateID == template.id ? .blue : .secondary)

                                Image(systemName: iconForTemplate(template.id))
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                    .frame(width: 32, height: 32)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(6)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name)
                                        .font(.headline)
                                    Text(template.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("Pre-installed: \(template.installedPackages.joined(separator: ", "))")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedTemplateID == template.id ? Color.blue : Color.primary.opacity(0.1), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
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
            Text("Hardware Resource Allocations (Smart Recommended)")
                .font(.headline)
            Text("Allocate host computer resources to the virtual environment. We recommended values optimized for the selected operating system and template.")
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
                    Text("Smart recommended cores for template: \(activeTemplate.recommendedCPU) Cores")
                        .font(.caption)
                        .foregroundStyle(.blue)

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
                    Text("Smart recommended RAM for template: \(String(format: "%.1f GB", Double(activeTemplate.recommendedRAM_MB) / 1024.0))")
                        .font(.caption)
                        .foregroundStyle(.blue)

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
                    Text("Smart recommended Storage: \(activeTemplate.recommendedStorage_GB) GB")
                        .font(.caption)
                        .foregroundStyle(.blue)
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
                            Text("Automatically map standard developer web ports (e.g. \(activeTemplate.defaultPorts.map(String.init).joined(separator: ", "))) to localhost.")
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
                        Text("Preset Template:")
                        Spacer()
                        Text(activeTemplate.name)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
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

    private func iconForTemplate(_ id: String) -> String {
        switch id {
        case "swift-server": return "swift"
        case "nodejs": return "curlybraces"
        case "python": return "doc.plaintext"
        case "rust": return "square.grid.3x3"
        case "go": return "network"
        case "docker": return "shippingbox"
        case "postgresql": return "externaldrive"
        case "redis": return "server.rack"
        case "ai-development": return "sparkles"
        default: return "terminal"
        }
    }

    private func createVM() {
        let ramMB = Int(memoryGB * 1024)
        let newVM = stateStore.createVM(
            name: vmName.isEmpty ? "\(selectedProviderName) \(activeTemplate.name)" : vmName,
            osType: selectedProviderName,
            version: activeProvider.versions.first ?? "Custom",
            cpu: Int(cpuCores),
            ramMB: ramMB,
            diskGB: Int(storageGB),
            imagePath: customImagePath.isEmpty ? nil : customImagePath
        )

        // Add template default ports if forwarding is checked
        if portForwarding {
            if let idx = stateStore.virtualMachines.firstIndex(where: { $0.id == newVM.id }) {
                stateStore.virtualMachines[idx].portForwardings = activeTemplate.defaultPorts.map { port in
                    VMPortForwarding(id: UUID(), name: "\(activeTemplate.name) Port", hostPort: port, guestPort: port)
                }
                try? VirtualMachineRegistry.shared.save(stateStore.virtualMachines)
            }
        }

        // Dispatch a build/timeline event
        WorkspaceTimelineManager.shared.addEvent(
            title: "VM Provisioned",
            detail: "Provisioned environment '\(newVM.name)' with \(newVM.cpuCores) cores and \(String(format: "%.1f GB", Double(newVM.memoryMB)/1024.0)) RAM.",
            category: "VM Started"
        )

        stateStore.showCreateWizard = false
    }
}
