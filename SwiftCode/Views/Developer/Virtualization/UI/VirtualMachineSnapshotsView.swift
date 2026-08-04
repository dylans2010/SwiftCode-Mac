import SwiftUI

public struct VirtualMachineSnapshotsView: View {
    public let vmID: UUID?

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var newSnapshotName: String = ""
    @State private var newSnapshotDesc: String = ""
    @State private var searchQuery: String = ""
    @State private var selectedSnapshotID: UUID? = nil

    public init(vmID: UUID?) {
        self.vmID = vmID
    }

    private var activeVM: VirtualMachine? {
        guard let id = vmID else { return stateStore.virtualMachines.first }
        return stateStore.virtualMachines.first { $0.id == id }
    }

    private var filteredSnapshots: [VMSnapshot] {
        guard let vm = activeVM else { return [] }
        if searchQuery.isEmpty {
            return vm.snapshots
        } else {
            return vm.snapshots.filter {
                $0.name.lowercased().contains(searchQuery.lowercased()) ||
                $0.description.lowercased().contains(searchQuery.lowercased())
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snapshot State Timeline")
                .font(.headline)
            Text("Create, compare, and revert to historical state snapshots of the environment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let vm = activeVM {
                // Creation card
                GroupBox(label: Text("Create Snapshot").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Snapshot Title (e.g. Pre-upgrade)", text: $newSnapshotName)
                                .textFieldStyle(.roundedBorder)

                            TextField("Brief Description / Reason", text: $newSnapshotDesc)
                                .textFieldStyle(.roundedBorder)

                            Button("Save Point") {
                                saveSnapshot(vm.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newSnapshotName.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Search Box
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search snapshots by title or description...", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.vertical, 4)

                // Timeline List & Compare Columns
                HStack(alignment: .top, spacing: 16) {
                    // Left: Timeline list
                    GroupBox(label: Text("Restoration Timeline").font(.headline)) {
                        VStack(alignment: .leading, spacing: 14) {
                            if filteredSnapshots.isEmpty {
                                Text("No matching recovery points found. Create one above.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 10)
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(filteredSnapshots) { snap in
                                            Button {
                                                selectedSnapshotID = snap.id
                                            } label: {
                                                HStack(alignment: .top, spacing: 12) {
                                                    VStack(spacing: 4) {
                                                        Image(systemName: selectedSnapshotID == snap.id ? "checkmark.circle.fill" : "circle.circle")
                                                            .font(.headline)
                                                            .foregroundStyle(selectedSnapshotID == snap.id ? .green : .blue)
                                                        Rectangle()
                                                            .fill(Color.secondary.opacity(0.3))
                                                            .frame(width: 2, height: 25)
                                                    }

                                                    VStack(alignment: .leading, spacing: 2) {
                                                        HStack {
                                                            Text(snap.name)
                                                                .font(.subheadline)
                                                                .fontWeight(.bold)
                                                                .foregroundStyle(.primary)
                                                            Spacer()
                                                            Text(snap.timestamp, style: .date)
                                                                .font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                        }

                                                        Text(snap.description)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer()
                                                }
                                                .padding(6)
                                                .background(selectedSnapshotID == snap.id ? Color.blue.opacity(0.08) : Color.clear)
                                                .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                            Divider()
                                        }
                                    }
                                }
                                .frame(height: 250)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .frame(maxWidth: .infinity)

                    // Right: Detailed Compare Inspector
                    if let selectedID = selectedSnapshotID,
                       let selectedSnap = vm.snapshots.first(where: { $0.id == selectedID }) {
                        GroupBox(label: Text("Snapshot Comparison Inspector").font(.headline)) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Snapshot Details:")
                                    .fontWeight(.bold)
                                    .font(.caption)

                                SCDetailRow(label: "Snapshot Name", value: selectedSnap.name)
                                SCDetailRow(label: "Reason/Notes", value: selectedSnap.description)
                                SCDetailRow(label: "Timestamp", value: formatDate(selectedSnap.timestamp))

                                Divider()

                                Text("Comparison with Active VM:")
                                    .fontWeight(.bold)
                                    .font(.caption)

                                SCDetailRow(label: "Active VM Cores", value: "\(vm.cpuCores) Cores")
                                SCDetailRow(label: "Active VM Memory", value: "\(vm.memoryMB) MB")
                                SCDetailRow(label: "Active VM Disk", value: "\(vm.storageGB) GB")

                                Divider()

                                HStack {
                                    Button("Revert VM to this State") {
                                        revertSnapshot(vm.id, snapID: selectedSnap.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)

                                    Button(role: .destructive) {
                                        deleteSnapshot(vm.id, snapID: selectedSnap.id)
                                        selectedSnapshotID = nil
                                    } label: {
                                        Text("Delete")
                                            .foregroundStyle(.red)
                                    }
                                    .controlSize(.small)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                        .frame(width: 320)
                    } else {
                        GroupBox {
                            VStack {
                                Spacer()
                                Image(systemName: "clock.arrow.2.circlepath")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Select a snapshot point to inspect historical specifications.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding()
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                        .frame(width: 320)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Virtual Machine",
                    systemImage: "clock.arrow.2.circlepath",
                    description: Text("Select an active VM from the sidebar to inspect and restore state snapshots.")
                )
            }
        }
    }

    private func saveSnapshot(_ vmID: UUID) {
        let name = newSnapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = newSnapshotDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        try? VMSnapshotManager.shared.createSnapshot(for: vmID, name: name, description: desc.isEmpty ? "Saved state" : desc)
        newSnapshotName = ""
        newSnapshotDesc = ""
        stateStore.refreshVM(vmID)
        stateStore.addLog("Snapshot '\(name)' recorded successfully.", type: .success)
    }

    private func revertSnapshot(_ vmID: UUID, snapID: UUID) {
        try? VMSnapshotManager.shared.restoreSnapshot(vmID: vmID, snapshotID: snapID)
        stateStore.refreshVM(vmID)
        stateStore.addLog("Reverted virtual machine to specified snapshot point.", type: .success)
    }

    private func deleteSnapshot(_ vmID: UUID, snapID: UUID) {
        try? VMSnapshotManager.shared.deleteSnapshot(vmID: vmID, snapshotID: snapID)
        stateStore.refreshVM(vmID)
        stateStore.addLog("Snapshot deleted from recovery index.", type: .warning)
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
