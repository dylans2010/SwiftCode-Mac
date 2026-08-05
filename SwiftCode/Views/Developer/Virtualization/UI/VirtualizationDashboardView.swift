import SwiftUI

public struct VirtualizationDashboardView: View {
    @State private var stateStore = VirtualizationStateStore.shared
    @State private var showingLearnMoreSheet = false
    @State private var showingFaqSheet = false

    public init() {}

    private var activeVMs: [VirtualMachine] {
        stateStore.virtualMachines.filter { $0.status == .running }
    }

    private var totalCores: Int {
        stateStore.virtualMachines.reduce(0) { $0 + $1.cpuCores }
    }

    private var totalRAM_GB: Double {
        Double(stateStore.virtualMachines.reduce(0) { $0 + $1.memoryMB }) / 1024.0
    }

    private var totalStorage_GB: Int {
        stateStore.virtualMachines.reduce(0) { $0 + $1.storageGB }
    }

    // Bookmarked or Favorited items
    private var bookmarkedVMs: [VirtualMachine] {
        stateStore.virtualMachines.filter { $0.isBookmarked || $0.isFavorite }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Dashboard Welcome Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dashboard")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Launch, configure, and monitor your isolated development sandboxes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        stateStore.showCreateWizard = true
                    } label: {
                        Label("New Environment", systemImage: "plus")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // CENTRAL SEARCH EVERYWHERE BOX
                GroupBox {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.blue)
                        TextField("Search everywhere across environments, templates, local images, snapshots, or logs...", text: $stateStore.searchEverywhereQuery)
                            .textFieldStyle(.plain)
                            .font(.headline)

                        if !stateStore.searchEverywhereQuery.isEmpty {
                            Button("Clear") {
                                stateStore.searchEverywhereQuery = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                if !stateStore.searchEverywhereQuery.isEmpty {
                    // Search everywhere layout overlay
                    searchEverywhereResultsView()
                } else {
                    // TRUE QUICK START HERO PANELS
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Start Guides")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            // Card 1: Create Environment
                            Button {
                                stateStore.showCreateWizard = true
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "cube.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.blue)
                                        .frame(width: 56, height: 56)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(12)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Create Development Environment")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                        Text("Deploy a fresh Linux environment optimized for development.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            // Card 2: Import Environment
                            Button {
                                importEnvironment()
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "square.and.arrow.down.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.purple)
                                        .frame(width: 56, height: 56)
                                        .background(Color.purple.opacity(0.1))
                                        .cornerRadius(12)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Import Existing Environment")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                        Text("Import a portable .json config package into your local registry.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            // Card 3: Browse Templates
                            Button {
                                stateStore.selectedSidebarTab = .environments
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "doc.text.image.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.orange)
                                        .frame(width: 56, height: 56)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(12)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Browse Service Templates")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                        Text("Choose from ready-made presets like Vapor, Node, and Docker.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            // Card 4: Learn Virtualization (Faq and Educational cards)
                            Button {
                                showingFaqSheet = true
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.green)
                                        .frame(width: 56, height: 56)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(12)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Virtualization FAQ Library")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                        Text("Discover snapshots, shared folders, and host sizing options.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // BOOKMARKED & FAVORITES SECTION (If available)
                    if !bookmarkedVMs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Bookmarked & Favorite Environments")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(bookmarkedVMs) { vm in
                                        Button {
                                            stateStore.selectedVMID = vm.id
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    Image(systemName: "bookmark.fill")
                                                        .foregroundStyle(.blue)
                                                    Spacer()
                                                    Circle()
                                                        .fill(vm.status == .running ? Color.green : Color.secondary)
                                                        .frame(width: 8, height: 8)
                                                }

                                                Text(vm.name)
                                                    .font(.headline)
                                                    .fontWeight(.bold)
                                                    .lineLimit(1)
                                                    .foregroundStyle(.primary)

                                                Text("\(vm.osType) • \(vm.cpuCores) Cores")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding()
                                            .frame(width: 180, height: 100)
                                            .background(Color(NSColor.controlBackgroundColor))
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // SMART HOST RECOMMENDATIONS & AUTO-OPTIMIZATION PANEL
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Smart Sizing & Recommendations")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        GroupBox(label:
                            HStack {
                                Label("Host Resources Evaluation", systemImage: "cpu.fill")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                Spacer()
                                Toggle("Enable Auto-Optimization", isOn: $stateStore.autoOptimizeResources)
                                    .toggleStyle(.checkbox)
                                    .fontWeight(.bold)
                            }
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                let hostCores = ProcessInfo.processInfo.activeProcessorCount
                                let hostMemoryGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

                                Text("SCVirtualizationKit has audited your Mac hardware: **\(hostCores) CPU Cores** and **\(hostMemoryGB) GB Physical RAM** are available.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if stateStore.autoOptimizeResources {
                                    HStack(spacing: 12) {
                                        Image(systemName: "checkmark.shield.fill")
                                            .foregroundStyle(.green)
                                            .font(.title2)
                                        Text("**Resource Auto-Optimization is ACTIVE:** Guest sandbox allocations will be automatically scaled down before provisioning if they exceed 50% of your Mac's physical bounds, ensuring macOS remains fast and responsive during heavy compiles.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(Color.green.opacity(0.08))
                                    .cornerRadius(6)
                                } else {
                                    HStack(spacing: 12) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                            .font(.title2)
                                        Text("**Auto-Optimization is Disabled:** Guest environments can allocate raw host boundaries. Be careful not to exceed physical Mac limits, which can cause frame stuttering or fan throttle on compiling.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(Color.orange.opacity(0.08))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // HEALTH & STATUS HUD PANELS
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Resource Health Overview")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            // Panel 1: Running Environments
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ACTIVE ENVIRONMENTS")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text("\(activeVMs.count) running")
                                            .font(.system(size: 22, weight: .bold))
                                        Spacer()
                                        Circle()
                                            .fill(activeVMs.isEmpty ? Color.secondary : Color.green)
                                            .frame(width: 12, height: 12)
                                    }
                                    Text("Out of \(stateStore.virtualMachines.count) total configured.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            // Panel 2: Host Allocation Summary
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("COMPUTE RESOURCES")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text("\(totalCores) Cores")
                                            .font(.system(size: 22, weight: .bold))
                                        Spacer()
                                        Text(String(format: "%.1f GB", totalRAM_GB))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.blue)
                                    }
                                    Text("Total CPU & memory allocated to registries.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            // Panel 3: Virtual Disk Utilisation
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("DISK RESERVATIONS")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text("\(totalStorage_GB) GB")
                                            .font(.system(size: 22, weight: .bold))
                                        Spacer()
                                        Image(systemName: "externaldrive")
                                            .foregroundStyle(.orange)
                                    }
                                    Text("Estimated virtual disk images on host.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                    }

                    // CONFIGURED ENVIRONMENTS SECTION
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Configured Environments")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        if stateStore.virtualMachines.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "cube.transparent")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                    .padding(.top)

                                Text("No Development Environments Yet")
                                    .font(.headline)

                                Text("Development environments let you build and test software in isolated Linux systems without affecting macOS.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 420)

                                Button {
                                    stateStore.showCreateWizard = true
                                } label: {
                                    Text("Create Your First Environment")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        } else {
                            VirtualMachineListView()
                        }
                    }

                    // RECENT ACTIVITY LOG
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity Logs")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                if stateStore.activityLogs.isEmpty {
                                    Text("No recent virtualization activity recorded.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 12)
                                } else {
                                    ForEach(stateStore.activityLogs.prefix(5)) { log in
                                        HStack(alignment: .center, spacing: 12) {
                                            Image(systemName: logIcon(log.type))
                                                .foregroundStyle(logColor(log.type))
                                                .font(.system(size: 14))

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(log.message)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                Text(log.timestamp, style: .time)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()

                                            Text(log.type.rawValue.uppercased())
                                                .font(.system(size: 8, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(logColor(log.type).opacity(0.12))
                                                .foregroundStyle(logColor(log.type))
                                                .cornerRadius(4)
                                        }
                                        .padding(.vertical, 4)

                                        if log.id != stateStore.activityLogs.prefix(5).last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingLearnMoreSheet) {
            learnMoreSheetContent()
        }
        .sheet(isPresented: $showingFaqSheet) {
            faqSheetContent()
        }
    }

    // SEARCH EVERYWHERE VIEW LAYOUT
    @ViewBuilder
    private func searchEverywhereResultsView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Search Everywhere Results")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Button("Clear Search") {
                    stateStore.searchEverywhereQuery = ""
                }
                .buttonStyle(.bordered)
            }

            let results = stateStore.searchEverywhereResults
            if results.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Results Found")
                        .font(.headline)
                    Text("No active environments, templates, local images, or snapshots match '\(stateStore.searchEverywhereQuery)'.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 10) {
                    ForEach(results) { item in
                        Button {
                            handleSearchSelection(item)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.icon)
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .frame(width: 36, height: 36)
                                    .background(Color.blue.opacity(0.08))
                                    .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(item.title)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(item.category.uppercased())
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12))
                                            .foregroundStyle(.secondary)
                                            .cornerRadius(4)
                                    }

                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func handleSearchSelection(_ item: SearchEverywhereItem) {
        stateStore.searchEverywhereQuery = ""
        if item.category == "Environment" {
            stateStore.selectedVMID = item.id
        } else if item.category == "Template" {
            stateStore.showCreateWizard = true
        } else if item.category == "Image" {
            stateStore.selectedSidebarTab = .images
        } else if item.category == "Snapshot" {
            stateStore.selectedSidebarTab = .snapshots
        }
    }

    @ViewBuilder
    private func learnMoreSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lightweight Development Virtualization")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Secure, Isolated, and blazing fast environments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    showingLearnMoreSheet = false
                }
                .buttonStyle(.bordered)
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Why use development environments?")
                    .font(.headline)

                Text("• **System Security:** Keep your primary host macOS clean. Any database setups, background compiler updates, and local server processes run inside the isolated sandboxed environment.")
                Text("• **Full Team Sync:** Share environment setup files (.json configs) with team members so everyone works on identical dependencies, ports, and packages.")
                Text("• **Fast Snapshots:** Instantly snapshot the state before performing library upgrades. If a package installation fails, revert back to the pristine state in less than a second.")
                Text("• **Deep Integration:** Share macOS project paths securely into the running container system to execute node, swift-server, docker, or python scripts seamlessly.")
            }
            .font(.subheadline)

            Spacer()
        }
        .padding(24)
        .frame(width: 520, height: 420)
    }

    @ViewBuilder
    private func faqSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Virtualization FAQ & Knowledge Base")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Lightweight, in-context educational guidelines.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    showingFaqSheet = false
                }
                .buttonStyle(.bordered)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    faqItem(q: "What is a Development Environment?", a: "An isolated guest operating system (VM) running secure, localized development and database tools. Keeping everything sandboxed prevents conflicting dependencies from corrupting your main macOS host configuration.")

                    faqItem(q: "When should I use Snapshots?", a: "Whenever you are about to perform high-risk actions—such as global package updates, custom toolchain modifications, or testing complex database migration scripts. A snapshot captures active state, letting you revert in less than a second if something breaks.")

                    faqItem(q: "Why use Shared Folders?", a: "Shared folders mount active macOS project directories directly into the guest VM filesystem (at `/mnt/workspace`). This enables you to write code in Xcode on your Mac while the guest environment handles compiles and runs instantly.")

                    faqItem(q: "How much RAM should I allocate?", a: "We recommend allocating about 4GB of RAM for lightweight boxes (such as node or database hosts), and 8GB or more for compile-heavy toolchains (like Swift backend and Vapor servers). Check Auto-Optimization to let SCVirtualizationKit balance sizing safely!")
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 540, height: 480)
    }

    @ViewBuilder
    private func faqItem(q: String, a: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(q)
                .font(.headline)
                .foregroundStyle(.blue)
            Text(a)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    private func logIcon(_ type: ActivityLog.LogType) -> String {
        switch type {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private func logColor(_ type: ActivityLog.LogType) -> Color {
        switch type {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func importEnvironment() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.json]
        if openPanel.runModal() == .OK, let url = openPanel.url {
            if let imported = try? VMBackupManager.shared.importConfiguration(from: url) {
                stateStore.refreshVM(imported.id)
                stateStore.selectedVMID = imported.id
                stateStore.addLog("Imported and activated development environment from \(url.lastPathComponent).", type: .success)
            }
        }
    }
}
