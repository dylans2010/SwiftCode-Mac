import SwiftUI

public struct VirtualizationDashboardView: View {
    @State private var stateStore = VirtualizationStateStore.shared
    @State private var showingLearnMoreSheet = false

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

                        // Card 4: Learn Virtualization
                        Button {
                            showingLearnMoreSheet = true
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "info.bubble.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.green)
                                    .frame(width: 56, height: 56)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(12)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Learn About Virtualization")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Text("Discover how isolated guest systems can secure your code.")
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
            .padding(24)
        }
        .sheet(isPresented: $showingLearnMoreSheet) {
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
