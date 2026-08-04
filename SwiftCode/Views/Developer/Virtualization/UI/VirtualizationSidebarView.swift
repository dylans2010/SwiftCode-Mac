import SwiftUI

public struct VirtualizationSidebarView: View {
    @State private var stateStore = VirtualizationStateStore.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Virtualization")
                        .font(.headline)
                    Text("SCVirtualizationKit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            // Sidebar Navigation Sections
            List {
                Section(header: Text("Workspace")) {
                    ForEach(VirtualizationStateStore.SidebarTab.allCases) { tab in
                        Button {
                            stateStore.selectedSidebarTab = tab
                            stateStore.selectedVMID = nil
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(stateStore.selectedSidebarTab == tab && stateStore.selectedVMID == nil ? .blue : .secondary)
                                Text(tab.rawValue)
                                    .font(.subheadline)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(stateStore.selectedSidebarTab == tab && stateStore.selectedVMID == nil ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                    }
                }

                Section(header: Text("Virtual Machines")) {
                    if stateStore.virtualMachines.isEmpty {
                        Text("No Virtual Machines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    } else {
                        ForEach(stateStore.virtualMachines) { vm in
                            Button {
                                stateStore.selectedVMID = vm.id
                            } label: {
                                HStack {
                                    Image(systemName: vm.status.icon)
                                        .foregroundStyle(statusColor(vm.status))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(vm.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("\(vm.osType) • \(vm.status.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 2)
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
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding()
        }
        .frame(minWidth: 220, maxHeight: .infinity)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
    }

    private func statusColor(_ status: VMStatus) -> Color {
        switch status {
        case .running: return .green
        case .starting, .resumed: return .blue
        case .stopped: return .secondary
        case .pausing, .paused: return .orange
        case .stopping: return .orange
        case .error: return .red
        }
    }
}
