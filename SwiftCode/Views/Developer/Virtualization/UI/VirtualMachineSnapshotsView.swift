import SwiftUI

public struct VirtualMachineSnapshotsView: View {
    public let vmID: UUID?

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var newSnapshotName: String = ""
    @State private var newSnapshotDesc: String = ""

    public init(vmID: UUID?) {
        self.vmID = vmID
    }

    private var activeVM: VirtualMachine? {
        guard let id = vmID else { return stateStore.virtualMachines.first }
        return stateStore.virtualMachines.first { $0.id == id }
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

                            TextField("Brief Description", text: $newSnapshotDesc)
                                .textFieldStyle(.roundedBorder)

                            Button("Save Point") {
                                saveSnapshot(vm.id)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Timeline List
                GroupBox(label: Text("Restoration Timeline").font(.headline)) {
                    VStack(alignment: .leading, spacing: 14) {
                        if vm.snapshots.isEmpty {
                            Text("No snapshot recovery points recorded yet. Type a title above to save a state snapshot.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(vm.snapshots) { snap in
                                HStack(alignment: .top, spacing: 12) {
                                    // Time Machine timeline bar effect
                                    VStack(spacing: 4) {
                                        Image(systemName: "clock.arrow.2.circlepath")
                                            .font(.headline)
                                            .foregroundStyle(.blue)
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.3))
                                            .frame(width: 2, height: 35)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(snap.name)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                            Spacer()
                                            Text(snap.timestamp, style: .date)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text(snap.timestamp, style: .time)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(snap.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        HStack(spacing: 10) {
                                            Button("Revert to Snapshot") {
                                                revertSnapshot(vm.id, snapID: snap.id)
                                            }
                                            .controlSize(.small)

                                            Button(role: .destructive) {
                                                deleteSnapshot(vm.id, snapID: snap.id)
                                            } label: {
                                                Text("Delete")
                                                    .foregroundStyle(.red)
                                            }
                                            .controlSize(.small)
                                        }
                                        .padding(.top, 4)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
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

        try? SnapshotManager.shared.createSnapshot(for: vmID, name: name, description: desc.isEmpty ? "Saved state" : desc)
        newSnapshotName = ""
        newSnapshotDesc = ""
        stateStore.refreshVM(vmID)
        stateStore.addLog("Snapshot '\(name)' recorded successfully.", type: .success)
    }

    private func revertSnapshot(_ vmID: UUID, snapID: UUID) {
        try? SnapshotManager.shared.restoreSnapshot(vmID: vmID, snapshotID: snapID)
        stateStore.refreshVM(vmID)
        stateStore.addLog("Reverted virtual machine to specified snapshot point.", type: .success)
    }

    private func deleteSnapshot(_ vmID: UUID, snapID: UUID) {
        try? SnapshotManager.shared.deleteSnapshot(vmID: vmID, snapshotID: snapID)
        stateStore.refreshVM(vmID)
        stateStore.addLog("Snapshot deleted from recovery index.", type: .warning)
    }
}
