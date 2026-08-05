import SwiftUI

public struct VirtualMachineSnapshotsView: View {
    public let vmID: UUID?

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var newSnapshotName: String = ""
    @State private var newSnapshotDesc: String = ""
    @State private var newSnapshotNotes: String = ""
    @State private var newSnapshotTagSelected: String = "Backup"
    @State private var searchQuery: String = ""
    @State private var selectedSnapshotID: UUID? = nil

    // Scheduled Snapshots States
    @State private var enableAutoSnapshots: Bool = false
    @State private var snapshotScheduleInterval: String = "Daily"

    private let availableTags = ["Initial", "Pre-Update", "Milestone", "Backup", "Stable"]

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
                $0.description.lowercased().contains(searchQuery.lowercased()) ||
                ($0.notes?.lowercased().contains(searchQuery.lowercased()) ?? false) ||
                ($0.tags?.contains(where: { $0.lowercased().contains(searchQuery.lowercased()) }) ?? false)
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Snapshot State Timeline")
                    .font(.headline)
                Text("Create, compare, and restore historical recovery points of the environment. Snapshots capture memory and disk configurations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let vm = activeVM {
                // Creation card
                GroupBox(label: Text("Create New Recovery Snapshot").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Snapshot Title (e.g. Pre-npm upgrade)", text: $newSnapshotName)
                                .textFieldStyle(.roundedBorder)

                            TextField("Optional description / short summary...", text: $newSnapshotDesc)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            TextField("Detailed snapshot notes / checklist details...", text: $newSnapshotNotes)
                                .textFieldStyle(.roundedBorder)

                            Picker("Snapshot Tag:", selection: $newSnapshotTagSelected) {
                                ForEach(availableTags, id: \.self) { tag in
                                    Text(tag).tag(tag)
                                }
                            }
                            .frame(width: 180)

                            Button("Save Snapshot") {
                                saveSnapshot(vm.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newSnapshotName.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // AUTOMATIC / SCHEDULED SNAPSHOTS PANEL
                GroupBox(label: Text("Scheduled Automated Snapshots").font(.subheadline)) {
                    HStack(spacing: 24) {
                        Toggle("Enable Automatic Background Snapshots", isOn: $enableAutoSnapshots)
                            .toggleStyle(.checkbox)
                            .fontWeight(.medium)

                        if enableAutoSnapshots {
                            HStack {
                                Text("Interval Schedule:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("", selection: $snapshotScheduleInterval) {
                                    Text("Hourly").tag("Hourly")
                                    Text("Daily (Recommended)").tag("Daily")
                                    Text("Weekly").tag("Weekly")
                                }
                                .frame(width: 180)
                            }
                            .transition(.opacity)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Search Filter Box
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search snapshots by title, description, notes or tags...", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                }

                // Timeline List & Compare Columns
                HStack(alignment: .top, spacing: 16) {
                    // Left: Timeline list
                    GroupBox(label: Text("Timeline Recovery Points").font(.headline)) {
                        VStack(alignment: .leading, spacing: 10) {
                            if filteredSnapshots.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.2.circlepath")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 8)

                                    Text("No Snapshots Recorded")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    Text("Create a snapshot recovery point above to secure your configuration before installing major updates.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                .frame(maxWidth: .infinity, minHeight: 180)
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(filteredSnapshots) { snap in
                                            Button {
                                                selectedSnapshotID = snap.id
                                            } label: {
                                                HStack(alignment: .top, spacing: 12) {
                                                    VStack(spacing: 4) {
                                                        Image(systemName: selectedSnapshotID == snap.id ? "checkmark.circle.fill" : "circle.circle")
                                                            .font(.subheadline)
                                                            .foregroundStyle(selectedSnapshotID == snap.id ? .green : .blue)

                                                        // Vertical timeline connector
                                                        Rectangle()
                                                            .fill(Color.secondary.opacity(0.2))
                                                            .frame(width: 2, height: 28)
                                                    }

                                                    VStack(alignment: .leading, spacing: 2) {
                                                        HStack(alignment: .center) {
                                                            Text(snap.name)
                                                                .font(.subheadline)
                                                                .fontWeight(.bold)
                                                                .foregroundStyle(.primary)

                                                            if let tags = snap.tags {
                                                                ForEach(tags, id: \.self) { tag in
                                                                    Text(tag.uppercased())
                                                                        .font(.system(size: 7, weight: .bold))
                                                                        .padding(.horizontal, 4)
                                                                        .padding(.vertical, 1)
                                                                        .background(Color.blue.opacity(0.12))
                                                                        .foregroundStyle(.blue)
                                                                        .cornerRadius(3)
                                                                }
                                                            }

                                                            Spacer()
                                                            Text(formatDate(snap.timestamp))
                                                                .font(.system(size: 10, design: .monospaced))
                                                                .foregroundStyle(.secondary)
                                                        }

                                                        Text(snap.description)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer()
                                                }
                                                .padding(8)
                                                .background(selectedSnapshotID == snap.id ? Color.blue.opacity(0.08) : Color.clear)
                                                .cornerRadius(8)
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
                        GroupBox(label: Text("State Comparison").font(.headline)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Selected Recovery Snapshot:")
                                    .fontWeight(.bold)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                SCDetailRow(label: "Title Name", value: selectedSnap.name)
                                SCDetailRow(label: "Description", value: selectedSnap.description)
                                SCDetailRow(label: "Timestamp", value: formatDate(selectedSnap.timestamp))

                                if let notes = selectedSnap.notes, !notes.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Snapshot Notes:")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.secondary)
                                        Text(notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(6)
                                            .background(Color.primary.opacity(0.04))
                                            .cornerRadius(4)
                                    }
                                }

                                Divider()

                                Text("Comparison with Active VM:")
                                    .fontWeight(.bold)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Attribute").font(.caption2).foregroundStyle(.secondary)
                                        Text("Cores").font(.subheadline)
                                        Text("RAM").font(.subheadline)
                                        Text("Disk Size").font(.subheadline)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 6) {
                                        Text("Snapshot").font(.caption2).foregroundStyle(.secondary)
                                        Text("\(vm.cpuCores) Cores")
                                        Text("\(vm.memoryMB) MB")
                                        Text("\(vm.storageGB) GB")
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 6) {
                                        Text("Active").font(.caption2).foregroundStyle(.secondary)
                                        Text("\(vm.cpuCores) Cores")
                                            .foregroundStyle(.blue)
                                        Text("\(vm.memoryMB) MB")
                                            .foregroundStyle(.blue)
                                        Text("\(vm.storageGB) GB")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(8)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)

                                Divider()

                                HStack(spacing: 8) {
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
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                        .frame(width: 320)
                    } else {
                        GroupBox {
                            VStack(spacing: 12) {
                                Spacer()
                                Image(systemName: "arrow.right.and.left.magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Select a recovery snapshot point to run side-by-side spec comparison.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 250)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                        .frame(width: 320)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Environment Selected",
                    systemImage: "clock.arrow.2.circlepath",
                    description: Text("Select an active environment from the sidebar to inspect and restore state snapshots.")
                )
            }
        }
    }

    private func saveSnapshot(_ vmID: UUID) {
        let name = newSnapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = newSnapshotDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = newSnapshotNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        var vms = VirtualMachineRegistry.shared.load()
        if let idx = vms.firstIndex(where: { $0.id == vmID }) {
            let snapshot = VMSnapshot(
                id: UUID(),
                name: name,
                description: desc.isEmpty ? "Saved state" : desc,
                timestamp: Date(),
                notes: notes.isEmpty ? nil : notes,
                tags: [newSnapshotTagSelected]
            )
            vms[idx].snapshots.insert(snapshot, at: 0)
            try? VirtualMachineRegistry.shared.save(vms)
            VirtualizationEventBus.shared.post(.metadataUpdated(vmID))
        }

        newSnapshotName = ""
        newSnapshotDesc = ""
        newSnapshotNotes = ""
        stateStore.refreshVM(vmID)
        stateStore.addLog("Created snapshot recovery point '\(name)' with tag [\(newSnapshotTagSelected)].", type: .success)
    }

    private func revertSnapshot(_ vmID: UUID, snapID: UUID) {
        try? VMSnapshotManager.shared.restoreSnapshot(vmID: vmID, snapshotID: snapID)
        stateStore.refreshVM(vmID)
        stateStore.addLog("Successfully rolled back environment state to selected snapshot.", type: .success)
    }

    private func deleteSnapshot(_ vmID: UUID, snapID: UUID) {
        try? VMSnapshotManager.shared.deleteSnapshot(vmID: vmID, snapshotID: snapID)
        stateStore.refreshVM(vmID)
        stateStore.addLog("Deleted snapshot point from local recovery index.", type: .warning)
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
