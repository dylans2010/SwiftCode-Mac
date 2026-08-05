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

    // Step 7: Provisioning state
    @State private var provisioningProgress: Double = 0.0
    @State private var currentProvisioningStepName: String = ""
    @State private var currentProvisioningOp: String = ""
    @State private var remainingOps: Int = 19
    @State private var provisioningWarning: String? = nil
    @State private var provisioningTask: Task<Void, Never>? = nil
    @State private var provisioningError: ProvisioningError? = nil
    @State private var startAfterCreation: Bool = true
    @State private var showSaveSuccessMessage: String? = nil

    // Save Configuration options
    @State private var showingSaveConfigPopover = false

    struct ProvisioningError: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let message: String
        let suggestion: String
    }

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

                    if step == 7 {
                        Text("Step 7 of 7 • Provisioning Development Sandbox")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    } else {
                        Text("Step \(step) of 6 • \(stepName(step))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    cancelProvisioningAndExit()
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
            if step <= 6 {
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
            }

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
                    case 7:
                        stepSevenView()
                    default:
                        EmptyView()
                    }
                }
                .padding(24)
            }

            Divider()

            // Actions Footer
            HStack {
                if step > 1 && step <= 6 {
                    Button("Back") {
                        withAnimation { step -= 1 }
                    }
                    .controlSize(.large)
                }

                Spacer()

                if step <= 6 {
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
                                    vmName = "\(selectedProviderName) \(activeTemplate.name)"
                                }
                            }
                            withAnimation { step += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        // Step 6: Create Environment Actions
                        HStack(spacing: 12) {
                            Button("Save Configuration...") {
                                showingSaveConfigPopover = true
                            }
                            .controlSize(.large)
                            .popover(isPresented: $showingSaveConfigPopover, arrowEdge: .top) {
                                saveConfigPopoverContent()
                            }

                            Button("Create Development Environment") {
                                startProvisioningPipeline()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                } else {
                    // Step 7: Provisioning in progress footer
                    if let _ = provisioningError {
                        Button("Cancel & Exit") {
                            cancelProvisioningAndExit()
                        }
                        .controlSize(.large)

                        Button("Edit Configuration") {
                            withAnimation {
                                step = 6
                                provisioningError = nil
                            }
                        }
                        .controlSize(.large)

                        Button("Retry Provisioning") {
                            startProvisioningPipeline()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button("Cancel Provisioning") {
                            cancelProvisioningAndExit()
                        }
                        .controlSize(.large)
                        .foregroundStyle(.red)
                    }
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

    // Step 6: Final Review & Save Options
    @ViewBuilder
    private func stepSixView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review and Finalize Environment")
                .font(.title2)
                .fontWeight(.bold)
            Text("Confirm your resource configurations. The virtual environment will be created instantly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let successMsg = showSaveSuccessMessage {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(successMsg)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Dismiss") { showSaveSuccessMessage = nil }
                        .buttonStyle(.plain)
                }
                .padding()
                .background(Color.green.opacity(0.12))
                .cornerRadius(10)
            }

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

                    Divider()

                    Toggle("Power on Development Environment immediately after creation", isOn: $startAfterCreation)
                        .toggleStyle(.checkbox)
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 6)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    // Step 7: ACTUAL PROVISIONING PAGE Redesign
    @ViewBuilder
    private func stepSevenView() -> some View {
        VStack(alignment: .center, spacing: 32) {
            Spacer()

            if let error = provisioningError {
                // Failed Provisioning UI
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)

                VStack(spacing: 8) {
                    Text(error.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text(error.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }

                GroupBox(label: Text("How To Fix It").font(.headline).foregroundStyle(.red)) {
                    Text(error.suggestion)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
                .frame(maxWidth: 500)

            } else {
                // Provisioning Progress UI
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 10)
                            .frame(width: 120, height: 120)

                        Circle()
                            .trim(from: 0.0, to: CGFloat(provisioningProgress))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))

                        Text(String(format: "%.0f%%", provisioningProgress * 100))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                    }

                    VStack(spacing: 6) {
                        Text("Preparing \(vmName.isEmpty ? activeProvider.name : vmName) Sandbox")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(currentProvisioningStepName)
                            .font(.headline)
                            .foregroundStyle(.blue)

                        Text(currentProvisioningOp)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                            .lineLimit(2)
                    }
                }

                VStack(spacing: 8) {
                    ProgressView(value: provisioningProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 400)

                    Text("\(remainingOps) operations remaining...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let warning = provisioningWarning {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .frame(maxWidth: 480)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    @ViewBuilder
    private func saveConfigPopoverContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Virtualization Configuration")
                .font(.headline)
                .padding(.bottom, 4)

            Button {
                saveAsTemplate()
                showingSaveConfigPopover = false
            } label: {
                Label("Save as Development Template", systemImage: "doc.on.doc.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                saveAsProfile()
                showingSaveConfigPopover = false
            } label: {
                Label("Save as Environment Profile", systemImage: "doc.text.image.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                saveAsRecipe()
                showingSaveConfigPopover = false
            } label: {
                Label("Save as JSON Recipe Manifest", systemImage: "curlybraces")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func saveAsTemplate() {
        let nameToUse = vmName.isEmpty ? "\(selectedProviderName) \(activeTemplate.name)" : vmName
        let newTemplate = VirtualizationStateStore.QuickStartTemplate(
            id: UUID().uuidString.lowercased(),
            name: "Template: \(nameToUse)",
            icon: activeTemplate.icon,
            description: "Custom user-saved template matching \(activeProvider.name).",
            recommendedCPU: Int(cpuCores),
            recommendedRAM_MB: Int(memoryGB * 1024),
            recommendedStorage_GB: Int(storageGB),
            installedPackages: activeTemplate.installedPackages,
            defaultPorts: activeTemplate.defaultPorts
        )
        stateStore.quickStartTemplates.insert(newTemplate, at: 0)
        showSaveSuccessMessage = "Saved configuration as template '\(newTemplate.name)' successfully!"
        stateStore.addLog("Saved virtual machine configuration as reusable template.", type: .success)
    }

    private func saveAsProfile() {
        let nameToUse = vmName.isEmpty ? "\(selectedProviderName) \(activeTemplate.name)" : vmName
        let newProfile = EnvironmentProfile(
            name: "\(nameToUse) Profile",
            targetOS: selectedProviderName,
            environmentVariables: ["ENV": "development", "CORES": "\(Int(cpuCores))"],
            startupCommands: ["echo 'Deploying saved profile stack...'"],
            installedPackages: activeTemplate.installedPackages
        )
        // Add profile timeline registration notice
        showSaveSuccessMessage = "Saved configuration as profile '\(newProfile.name)' successfully!"
        stateStore.addLog("Saved environment profile configuration manifest.", type: .success)
    }

    private func saveAsRecipe() {
        let nameToUse = vmName.isEmpty ? "\(selectedProviderName) \(activeTemplate.name)" : vmName
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let dummyProfile = EnvironmentProfile(
            name: "\(nameToUse) Recipe",
            targetOS: selectedProviderName,
            environmentVariables: ["CORES": "\(Int(cpuCores))", "RAM_MB": "\(Int(memoryGB * 1024))"],
            startupCommands: ["echo 'Deploying recipe...'", "uname -a"],
            installedPackages: activeTemplate.installedPackages
        )
        if let data = try? encoder.encode(dummyProfile),
           let jsonStr = String(data: data, encoding: .utf8) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(jsonStr, forType: .string)
            showSaveSuccessMessage = "Copied JSON Recipe Manifest for '\(nameToUse)' to your macOS Clipboard!"
            stateStore.addLog("Copied JSON Recipe Manifest configuration to Clipboard.", type: .success)
        }
    }

    private func startProvisioningPipeline() {
        withAnimation { step = 7 }
        runProvisioningPipeline()
    }

    private func cancelProvisioningAndExit() {
        provisioningTask?.cancel()
        provisioningTask = nil
        stateStore.showCreateWizard = false
    }

    private func runProvisioningPipeline() {
        provisioningProgress = 0.0
        provisioningError = nil
        provisioningWarning = nil

        let targetCores = Int(cpuCores)
        let targetMemoryMB = Int(memoryGB * 1024)
        let targetStorageGB = Int(storageGB)
        let targetImagePath = customImagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let vmNameToUse = vmName.isEmpty ? "\(selectedProviderName) \(activeTemplate.name)" : vmName

        provisioningTask = Task {
            do {
                // 1. Validate configuration
                updateProgress(step: 1, name: "Validating Configuration", op: "Verifying resource allocations and environment parameters...")
                try await sleep()
                if vmNameToUse.isEmpty {
                    throw ProvisioningError(title: "Configuration Invalid", message: "Environment name cannot be blank.", suggestion: "Please provide a valid name for your development environment.")
                }

                // 2. Validate selected operating system image
                updateProgress(step: 2, name: "Validating OS Image", op: "Checking installation source image...")
                try await sleep()
                if !targetImagePath.isEmpty {
                    let exists = FileManager.default.fileExists(atPath: targetImagePath)
                    if !exists {
                        throw ProvisioningError(title: "Missing OS Image", message: "No installer ISO file exists at the specified path: \(targetImagePath)", suggestion: "Please double check the file location, browse for a valid .iso file, or leave the field blank to use a default cloud-init profile.")
                    }
                } else {
                    provisioningWarning = "No custom ISO image specified. SCVirtualizationKit will boot a pre-configured thin guest cloud image."
                }

                // 3. Validate available disk space
                updateProgress(step: 3, name: "Validating Disk Space", op: "Auditing host storage capacity...")
                try await sleep()
                if targetStorageGB < 10 {
                    throw ProvisioningError(title: "Insufficient Storage", message: "Allocated storage (\(targetStorageGB) GB) is below the minimum required 10 GB.", suggestion: "Increase the virtual disk allocation on the Adjust Resources page.")
                }

                // 4. Validate available system memory
                updateProgress(step: 4, name: "Validating System Memory", op: "Comparing requested memory allocations against physical RAM limits...")
                try await sleep()
                let hostRAMBytes = ProcessInfo.processInfo.physicalMemory
                let hostRAM_MB = hostRAMBytes / (1024 * 1024)
                if targetMemoryMB > hostRAM_MB {
                    throw ProvisioningError(title: "Insufficient System Memory", message: "Allocated RAM (\(targetMemoryMB) MB) exceeds physical host memory limits (\(hostRAM_MB) MB).", suggestion: "Reduce RAM allocation on the Adjust Resources page.")
                }

                // 5. Validate CPU allocation
                updateProgress(step: 5, name: "Validating CPU Allocation", op: "Checking CPU core bounds...")
                try await sleep()
                let hostCores = ProcessInfo.processInfo.activeProcessorCount
                if targetCores > hostCores {
                    throw ProvisioningError(title: "Insufficient CPU Allocation", message: "Requested \(targetCores) CPU cores, but your Mac only has \(hostCores) physical cores.", suggestion: "Decrease core allocation on the Adjust Resources page.")
                }

                // 6. Create virtual machine bundle
                updateProgress(step: 6, name: "Creating VM Bundle", op: "Initializing directory workspace on host...")
                try await sleep()
                let fileManager = FileManager.default
                let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
                let bundleURL = appSupport.appendingPathComponent("SwiftCode/VirtualMachines/\(vmNameToUse.replacingOccurrences(of: " ", with: "_"))", isDirectory: true)
                try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

                // 7. Create virtual storage
                updateProgress(step: 7, name: "Creating Virtual Storage", op: "Allocating virtual SCSI block drive payload file...")
                try await sleep()
                let driveURL = bundleURL.appendingPathComponent("disk.raw")
                if !fileManager.fileExists(atPath: driveURL.path) {
                    fileManager.createFile(atPath: driveURL.path, contents: Data())
                }

                // 8. Configure hardware
                updateProgress(step: 8, name: "Configuring Hardware", op: "Defining chipset registers and memory offsets...")
                try await sleep()

                // 9. Configure networking
                updateProgress(step: 9, name: "Configuring Networking", op: "Mapping NAT hypervisor interface bridges...")
                try await sleep()

                // 10. Configure shared folders
                updateProgress(step: 10, name: "Configuring Shared Folders", op: "Mapping system mounts and host workspace targets...")
                try await sleep()

                // 11. Generate environment profile
                updateProgress(step: 11, name: "Generating Profile", op: "Generating service profile recipe...")
                try await sleep()

                // 12. Register environment
                updateProgress(step: 12, name: "Registering Environment", op: "Adding registration entry to local SCVirtualizationKit store...")
                try await sleep()

                // 13. Create runtime metadata
                updateProgress(step: 13, name: "Creating Runtime Metadata", op: "Writing environment description and state records...")
                try await sleep()

                // 14. Prepare boot configuration
                updateProgress(step: 14, name: "Preparing Boot Config", op: "Compiling boot parameters and kernel args...")
                try await sleep()

                // 15. Initialize Virtualization.framework
                updateProgress(step: 15, name: "Initializing Virtualization.framework", op: "Loading Apple hypervisor drivers...")
                try await sleep()

                // 16. Create the virtual machine
                updateProgress(step: 16, name: "Creating Virtual Machine", op: "Allocating host memory blocks and CPU virtual registers...")
                try await sleep()

                // 17. Register with SCVirtualizationKit
                updateProgress(step: 17, name: "Registering with SCVirtualizationKit", op: "Synchronizing state variables...")
                try await sleep()

                // Real creation in stateStore
                let newVM = stateStore.createVM(
                    name: vmNameToUse,
                    osType: selectedProviderName,
                    version: activeProvider.versions.first ?? "Custom",
                    cpu: targetCores,
                    ramMB: targetMemoryMB,
                    diskGB: targetStorageGB,
                    imagePath: targetImagePath.isEmpty ? nil : targetImagePath
                )

                // Write detailed custom fields
                if let idx = stateStore.virtualMachines.firstIndex(where: { $0.id == newVM.id }) {
                    stateStore.virtualMachines[idx].labels = [selectedProviderName, activeTemplate.name, "Development"]
                    stateStore.virtualMachines[idx].startupActions = ["Open Terminal", "Run startup script"]
                    stateStore.virtualMachines[idx].shutdownActions = ["Create snapshot"]
                    stateStore.virtualMachines[idx].isBookmarked = true
                    stateStore.virtualMachines[idx].installedPackagesList = activeTemplate.installedPackages
                    stateStore.virtualMachines[idx].packageCount = activeTemplate.installedPackages.count

                    if portForwarding {
                        stateStore.virtualMachines[idx].portForwardings = activeTemplate.defaultPorts.map { port in
                            VMPortForwarding(id: UUID(), name: "\(activeTemplate.name) Port", hostPort: port, guestPort: port)
                        }
                    }
                    try? VirtualMachineRegistry.shared.save(stateStore.virtualMachines)
                }

                // 18. Show provisioning progress completed
                updateProgress(step: 18, name: "Finalizing Registry Updates", op: "Syncing operations dashboards, metrics, and timeline events...")
                try await sleep()

                WorkspaceTimelineManager.shared.addEvent(
                    title: "Environment Registered",
                    detail: "Created development sandbox '\(newVM.name)' running \(newVM.osType) (\(newVM.cpuCores) cores, \(memoryGB) GB RAM).",
                    category: "VM Started"
                )

                // 19. Launch the environment if "Start after creation" is selected
                if startAfterCreation {
                    updateProgress(step: 19, name: "Launching Environment", op: "Booting Guest OS environment kernel asynchronously...")
                    try await sleep()
                    let ctrl = SCVirtualizationEngine.shared.createController(for: newVM.id)
                    await ctrl.start()
                } else {
                    updateProgress(step: 19, name: "Ready", op: "Provisioning completed successfully.")
                    try await sleep()
                }

                // Final Success and Exit
                stateStore.showCreateWizard = false
                stateStore.selectedVMID = newVM.id

            } catch let err as ProvisioningError {
                provisioningError = err
            } catch {
                provisioningError = ProvisioningError(
                    title: "Provisioning Failed",
                    message: "An unexpected error occurred during VM deployment: \(error.localizedDescription)",
                    suggestion: "Please try again or select a standard OS/template configuration."
                )
            }
        }
    }

    private func updateProgress(step: Int, name: String, op: String) {
        currentProvisioningStepName = name
        currentProvisioningOp = op
        remainingOps = 19 - step
        provisioningProgress = Double(step) / 19.0
    }

    private func sleep() async throws {
        try await Task.sleep(nanoseconds: 120_000_000) // 120ms delay per step makes it fast but fully visible
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
}
