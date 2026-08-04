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

    // Step 2: Template Selection
    @State private var selectedTemplateID: String = "blank"

    // Step 3: Configure Resources
    @State private var cpuCores: Double = 4
    @State private var memoryGB: Double = 8
    @State private var storageGB: Double = 64
    @State private var showingAdvancedResources = false

    // Step 4: Select Image
    @State private var customImagePath: String = ""

    // Step 5: Configure Features
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

    // Estimated impact calculation
    private var hostImpactDescription: (text: String, color: Color, icon: String) {
        if cpuCores <= 2 && memoryGB <= 4 {
            return ("Light impact on your Mac. Ideal for background servers and lightweight tasks.", .green, "leaf.fill")
        } else if cpuCores <= 4 && memoryGB <= 8 {
            return ("Balanced impact. Optimal mix of guest performance and host battery life.", .blue, "checkmark.circle.fill")
        } else {
            return ("High impact. Guest will compile extremely fast, but high host resource usage may trigger fans.", .orange, "exclamationmark.triangle.fill")
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title Header with Step Indicator
            HStack(spacing: 16) {
                Image(systemName: "cube.fill")
                    .font(.title)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup Development Environment")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Step \(step) of 6 • \(stepName(step))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    stateStore.showCreateWizard = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Horizontal step progress bubbles
            HStack(spacing: 8) {
                ForEach(1...6, id: \.self) { s in
                    HStack {
                        Circle()
                            .fill(step == s ? Color.blue : (step > s ? Color.blue.opacity(0.4) : Color.secondary.opacity(0.2)))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Text("\(s)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            )

                        if s < 6 {
                            Rectangle()
                                .fill(step > s ? Color.blue : Color.secondary.opacity(0.15))
                                .frame(height: 2)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Wizard Body Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
                    case 6:
                        stepSixView()
                    default:
                        EmptyView()
                    }
                }
                .padding(24)
            }

            Divider()

            // Actions Footer
            HStack {
                if step > 1 {
                    Button("Back") {
                        withAnimation { step -= 1 }
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
                            applySmartRecommendations()
                        } else if step == 2 {
                            applySmartRecommendations()
                            if vmName.isEmpty {
                                vmName = "\(activeProvider.name) \(activeTemplate.name)"
                            }
                        }
                        withAnimation { step += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Create Environment") {
                        createEnvironment()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 700, minHeight: 550)
    }

    private func stepName(_ step: Int) -> String {
        switch step {
        case 1: return "Choose Operating System"
        case 2: return "Choose Template"
        case 3: return "Adjust Resources"
        case 4: return "Select Image File"
        case 5: return "Customizations"
        case 6: return "Review & Create"
        default: return ""
        }
    }

    private func applySmartRecommendations() {
        let recs = stateStore.getSmartRecommendation(osType: selectedProviderName, templateID: selectedTemplateID)
        cpuCores = Double(recs.cores)
        memoryGB = Double(recs.memoryMB) / 1024.0
        storageGB = Double(recs.storageGB)
    }

    // Step 1: OS Selection (With Logos & Specifications)
    @ViewBuilder
    private func stepOneView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select an Operating System")
                .font(.title2)
                .fontWeight(.bold)
            Text("Each operating system is fine-tuned and fully optimized for development toolchains on Apple Silicon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(providers, id: \.name) { prov in
                    Button {
                        selectedProviderName = prov.name
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: selectedProviderName == prov.name ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedProviderName == prov.name ? .blue : .secondary)

                            Image(systemName: provSystemIcon(prov.name))
                                .font(.title)
                                .foregroundStyle(provColor(prov.name))
                                .frame(width: 48, height: 48)
                                .background(provColor(prov.name).opacity(0.1))
                                .cornerRadius(10)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(prov.name)
                                        .font(.headline)
                                    Text("• Optimized")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                        .fontWeight(.bold)
                                }
                                Text(prov.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                Text("Requires: \(prov.recommendedCPU) Cores • \(prov.recommendedRAM) RAM • \(prov.recommendedStorage) Disk • \(prov.supportedArchitectures)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedProviderName == prov.name ? Color.blue : Color.primary.opacity(0.08), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Step 2: Choose Template
    @ViewBuilder
    private func stepTwoView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a Development Template")
                .font(.title2)
                .fontWeight(.bold)
            Text("Templates configure recommended hardware parameters and automate package management installations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(stateStore.quickStartTemplates) { template in
                    Button {
                        selectedTemplateID = template.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedTemplateID == template.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedTemplateID == template.id ? .blue : .secondary)

                            Image(systemName: iconForTemplate(template.id))
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .frame(width: 36, height: 36)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)
                                Text(template.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedTemplateID == template.id ? Color.blue : Color.primary.opacity(0.08), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Step 3: Configure Resources (With Presets + Host Impact HUD)
    @ViewBuilder
    private func stepThreeView() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hardware Configuration")
                .font(.title2)
                .fontWeight(.bold)
            Text("Configure allocated hardware capabilities. Smart recommendations have been pre-applied.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Resource Presets Buttons
            HStack(spacing: 12) {
                presetButton(title: "Small Node", desc: "2 Cores • 4 GB RAM", cores: 2, ram: 4, disk: 40)
                presetButton(title: "Balanced Stack", desc: "4 Cores • 8 GB RAM", cores: 4, ram: 8, disk: 64)
                presetButton(title: "Heavy Compiler", desc: "6 Cores • 16 GB RAM", cores: 6, ram: 16, disk: 100)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    // CPU Cores Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("CPU Allocation:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(Int(cpuCores)) Cores")
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }
                        Slider(value: $cpuCores, in: 1...16, step: 1)
                        HStack {
                            Text("Minimum: 1 Core").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("Template Recommended: \(activeTemplate.recommendedCPU)").font(.caption2).foregroundStyle(.blue)
                        }
                    }

                    Divider()

                    // RAM Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Memory (RAM):")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f GB", memoryGB))
                                .font(.headline)
                                .foregroundStyle(.purple)
                        }
                        Slider(value: $memoryGB, in: 1...64, step: 0.5)
                        HStack {
                            Text("Minimum: 1 GB").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("Template Recommended: \(String(format: "%.1f GB", Double(activeTemplate.recommendedRAM_MB)/1024.0))").font(.caption2).foregroundStyle(.purple)
                        }
                    }

                    Divider()

                    // Disk Drive Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Virtual Disk Size:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(Int(storageGB)) GB")
                                .font(.headline)
                                .foregroundStyle(.orange)
                        }
                        Slider(value: $storageGB, in: 10...500, step: 5)
                        HStack {
                            Text("Minimum: 10 GB").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("Template Recommended: \(activeTemplate.recommendedStorage_GB) GB").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Host Impact HUD Bar
            HStack(spacing: 12) {
                Image(systemName: hostImpactDescription.icon)
                    .font(.title2)
                    .foregroundStyle(hostImpactDescription.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Performance Estimation:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text(hostImpactDescription.text)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(hostImpactDescription.color)
                }
                Spacer()
            }
            .padding()
            .background(hostImpactDescription.color.opacity(0.1))
            .cornerRadius(10)
        }
    }

    // Step 4: Choose Image File
    @ViewBuilder
    private func stepFourView() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Select Installation Source File")
                .font(.title2)
                .fontWeight(.bold)
            Text("Specify the raw operating system image file (.iso or .img) to install inside the virtual workspace.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Official distribution download portal for \(activeProvider.name):")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Always download genuine operating system disk images. Links are secure and official.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "link.circle.fill")
                            .foregroundStyle(.blue)
                        Text(activeProvider.officialDownloadPage)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button("Visit Download Site") {
                            if let url = URL(string: activeProvider.officialDownloadPage) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.12))
                    .cornerRadius(6)
                }
                .padding(.vertical, 4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            GroupBox(label: Text("Local Image Selection").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Path to downloaded ISO file on your Mac...", text: $customImagePath)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Browse Files...") {
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
                        Text("Expected formats: \(activeProvider.supportedImageFormats.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    // Step 5: Advanced Development Customizations
    @ViewBuilder
    private func stepFiveView() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Customizations & Advanced Integration")
                .font(.title2)
                .fontWeight(.bold)
            Text("Enable native integration capabilities to connect your workspace seamlessly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Simple switches
            VStack(spacing: 12) {
                Toggle(isOn: $shareFolders) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mount Shared Project Directories")
                            .fontWeight(.medium)
                        Text("Instantly mount active SwiftCode projects into the guest workspace at /mnt/workspace.")
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
                        Text("Copy and paste code text easily between host macOS and guest shell sessions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Divider()

                Toggle(isOn: $networkAccess) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NAT Hypervisor Connection Adapter")
                            .fontWeight(.medium)
                        Text("Secure internet address translation allowing safe package updates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

            // Progressive disclosure for Advanced Options
            DisclosureGroup(isExpanded: $showingAdvancedResources) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Automatic Hypervisor Recovery Points", isOn: $automaticSnapshots)
                        .toggleStyle(.checkbox)

                    Toggle("Port Forwarding (Localhost ➔ Guest Standard Developer Ports)", isOn: $portForwarding)
                        .toggleStyle(.checkbox)

                    Toggle("Configure Background Guest Agent (Highly Recommended)", isOn: $terminalAccess)
                        .toggleStyle(.checkbox)
                }
                .padding()
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .padding(.top, 4)
            } label: {
                Text("Show Advanced Virtualization Options...")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    // Step 6: Final Review & Create
    @ViewBuilder
    private func stepSixView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review and Finalize Environment")
                .font(.title2)
                .fontWeight(.bold)
            Text("Confirm your resource configurations. The virtual environment will be created instantly.")
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

                    SCDetailRow(label: "Operating System Provider", value: activeProvider.name)
                    SCDetailRow(label: "Target Preset Template", value: activeTemplate.name)
                    SCDetailRow(label: "CPU Allocations", value: "\(Int(cpuCores)) Cores")
                    SCDetailRow(label: "Memory (RAM)", value: String(format: "%.1f GB", memoryGB))
                    SCDetailRow(label: "Hard Drive Size", value: "\(Int(storageGB)) GB")
                    SCDetailRow(label: "Installation Source", value: customImagePath.isEmpty ? "Direct ISO Download Option" : customImagePath)

                    Divider()

                    Text("Enabled Developer Modules:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        badgeTag(text: "Shared Folders", enabled: shareFolders)
                        badgeTag(text: "NAT Network", enabled: networkAccess)
                        badgeTag(text: "Port Maps", enabled: portForwarding)
                        badgeTag(text: "Clipboard", enabled: clipboardSharing)
                    }
                }
                .padding(.vertical, 6)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    @ViewBuilder
    private func presetButton(title: String, desc: String, cores: Int, ram: Double, disk: Double) -> some View {
        Button {
            cpuCores = Double(cores)
            memoryGB = ram
            storageGB = disk
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func badgeTag(text: String, enabled: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(enabled ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.1))
            .foregroundStyle(enabled ? Color.blue : Color.secondary)
            .cornerRadius(4)
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

    private func createEnvironment() {
        let ramMB = Int(memoryGB * 1024)
        let nameToUse = vmName.isEmpty ? "\(selectedProviderName) \(activeTemplate.name)" : vmName

        let newVM = stateStore.createVM(
            name: nameToUse,
            osType: selectedProviderName,
            version: activeProvider.versions.first ?? "Custom",
            cpu: Int(cpuCores),
            ramMB: ramMB,
            diskGB: Int(storageGB),
            imagePath: customImagePath.isEmpty ? nil : customImagePath
        )

        // Set templates default ports if port forwarding is enabled
        if portForwarding {
            if let idx = stateStore.virtualMachines.firstIndex(where: { $0.id == newVM.id }) {
                stateStore.virtualMachines[idx].portForwardings = activeTemplate.defaultPorts.map { port in
                    VMPortForwarding(id: UUID(), name: "\(activeTemplate.name) Port", hostPort: port, guestPort: port)
                }
                try? VirtualMachineRegistry.shared.save(stateStore.virtualMachines)
            }
        }

        // Add timeline event
        WorkspaceTimelineManager.shared.addEvent(
            title: "Environment Created",
            detail: "Created '\(newVM.name)' running \(newVM.osType) with \(newVM.cpuCores) cores and \(Int(memoryGB))GB RAM.",
            category: "VM Started"
        )

        stateStore.showCreateWizard = false
    }
}
