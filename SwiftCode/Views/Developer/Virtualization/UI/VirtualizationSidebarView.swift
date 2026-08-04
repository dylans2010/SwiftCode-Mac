import SwiftUI

public struct VirtualizationSidebarView: View {
    @State private var stateStore = VirtualizationStateStore.shared
    @State private var showingAdvancedResources: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer Environments")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("SCVirtualizationKit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            // Sidebar Navigation Sections
            List {
                Section(header: Text("Workspace").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)) {
                    sidebarRow(tab: .dashboard, title: "Dashboard", icon: "square.grid.2x2.fill")
                    sidebarRow(tab: .environments, title: "Profiles & Templates", icon: "doc.text.image.fill")
                }

                Section(header: Text("Library").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)) {
                    sidebarRow(tab: .images, title: "OS Image Catalog", icon: "opticaldisc.fill")
                }

                Section(header: Text("Resources").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)) {
                    DisclosureGroup(isExpanded: $showingAdvancedResources) {
                        VStack(alignment: .leading, spacing: 2) {
                            sidebarRow(tab: .storage, title: "Storage Volumes", icon: "externaldrive.fill")
                            sidebarRow(tab: .networking, title: "Network NAT", icon: "network")
                            sidebarRow(tab: .snapshots, title: "Recovery Snapshots", icon: "clock.arrow.2.circlepath")
                        }
                        .padding(.leading, 8)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                                .frame(width: 18, height: 18)
                                .foregroundStyle(.secondary)
                            Text("Advanced Tools")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section(header: Text("Application").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)) {
                    sidebarRow(tab: .settings, title: "Preferences", icon: "gearshape.fill")
                }

                Section(header: Text("Development Environments").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)) {
                    if stateStore.virtualMachines.isEmpty {
                        Text("No Environments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                            .padding(.vertical, 4)
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
        .frame(minWidth: 240, maxHeight: .infinity)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
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
