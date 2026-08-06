import SwiftUI

public struct VirtualizationSidebarView: View {
    @State private var stateStore = VirtualizationStateStore.shared
    @AppStorage("com.swiftcode.virtualization.sidebarWidth") private var sidebarWidth: Double = 240
    @AppStorage("com.swiftcode.virtualization.sidebarCollapsed") private var isSidebarCollapsed: Bool = false

    public init() {}

    public var body: some View {
        if isSidebarCollapsed {
            VStack {
                Button {
                    isSidebarCollapsed = false
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.title3)
                        .padding(8)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .frame(width: 44)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Polished Header (native-styled title bar inspector block)
                HStack(spacing: 10) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Virtualization Panel")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("SwiftCode Hypervisor Engine")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Button {
                        isSidebarCollapsed = true
                    } label: {
                        Image(systemName: "sidebar.left")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse Sidebar")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Main Sidebar List
                List {
                    Section(header: Text("DASHBOARD").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)) {
                        sidebarRow(tab: .dashboard, title: "Dashboard", icon: "square.grid.2x2.fill")
                        sidebarRow(tab: .vmLibrary, title: "VM Library", icon: "cube.transparent.fill")
                        sidebarRow(tab: .activeSessions, title: "Active Sessions", icon: "play.circle.fill")
                    }

                    Section(header: Text("RESOURCES").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)) {
                        sidebarRow(tab: .storage, title: "Storage", icon: "externaldrive.fill")
                        sidebarRow(tab: .networking, title: "Networking", icon: "network")
                        sidebarRow(tab: .snapshots, title: "Snapshots", icon: "clock.arrow.2.circlepath")
                        sidebarRow(tab: .sharedFolders, title: "Shared Folders", icon: "folder.badge.person.crop")
                    }

                    Section(header: Text("HARDWARE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)) {
                        sidebarRow(tab: .displays, title: "Displays", icon: "monitor")
                        sidebarRow(tab: .devices, title: "Devices", icon: "ipad.and.iphone")
                    }

                    Section(header: Text("DIAGNOSTICS").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)) {
                        sidebarRow(tab: .console, title: "Console", icon: "terminal.fill")
                        sidebarRow(tab: .logs, title: "Logs", icon: "doc.text.fill")
                        sidebarRow(tab: .performance, title: "Performance", icon: "chart.bar.fill")
                    }

                    Section(header: Text("SYSTEM").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)) {
                        sidebarRow(tab: .settings, title: "Settings", icon: "gearshape.fill")
                    }

                    Section(header: Text("ENVIRONMENTS").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)) {
                        if stateStore.virtualMachines.isEmpty {
                            Text("No Environments")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        } else {
                            ForEach(stateStore.virtualMachines) { vm in
                                Button {
                                    stateStore.selectedVMID = vm.id
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(statusColor(vm.status))
                                            .frame(width: 8, height: 8)
                                            .padding(.trailing, 4)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(vm.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                            Text("\(vm.osType) • \(vm.status.rawValue)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()

                                        if vm.status == .running {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 8))
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(stateStore.selectedVMID == vm.id ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                Spacer()

                // Bottom Action
                Button {
                    stateStore.showCreateWizard = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("New Environment")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding()
            }
            .frame(width: sidebarWidth)
            .frame(maxHeight: .infinity)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        }
    }

    @ViewBuilder
    private func sidebarRow(tab: VirtualizationStateStore.SidebarTab, title: String, icon: String) -> some View {
        let isSelected = stateStore.selectedSidebarTab == tab && stateStore.selectedVMID == nil
        Button {
            stateStore.selectedSidebarTab = tab
            stateStore.selectedVMID = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .medium : .regular)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
    }

    private func statusColor(_ status: VMStatus) -> Color {
        switch status {
        case .running: return .green
        case .starting: return .blue
        case .stopped: return .secondary
        case .pausing, .paused: return .orange
        case .stopping: return .orange
        case .error: return .red
        }
    }
}
