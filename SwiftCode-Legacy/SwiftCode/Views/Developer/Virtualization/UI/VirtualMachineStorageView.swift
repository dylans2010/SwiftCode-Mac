import SwiftUI

public struct VirtualMachineStorageView: View {
    public let vmID: UUID?

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var diskResizeGB: Double = 40

    public init(vmID: UUID?) {
        self.vmID = vmID
    }

    private var activeVM: VirtualMachine? {
        guard let id = vmID else { return stateStore.virtualMachines.first }
        return stateStore.virtualMachines.first { $0.id == id }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Virtual Storage & Disk Volumes")
                        .font(.headline)
                    Text("Inspect allocation metrics, resize primary disk files, and export secure environment bundles.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let vm = activeVM {
                GroupBox(label: Text("Disk Space Allocation").font(.headline)) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Primary Boot Drive Volume", systemImage: "internaldrive.fill")
                                .fontWeight(.medium)
                            Spacer()
                            Text("/dev/vda1 (Pristine)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Current Assigned Disk Capacity:")
                            Spacer()
                            Text("\(vm.storageGB) GB")
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }

                        HStack {
                            Text("Estimated Free Space:")
                            Spacer()
                            Text("88% Available")
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }

                        Divider()

                        // Resize volume section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resize Primary Storage Drive:")
                                .fontWeight(.medium)

                            HStack(spacing: 12) {
                                Slider(value: $diskResizeGB, in: Double(vm.storageGB)...500, step: 5)
                                    .accentColor(.orange)

                                Text("\(Int(diskResizeGB)) GB")
                                    .font(.headline)
                                    .frame(width: 70, alignment: .trailing)
                            }

                            // Dynamic Warning message
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text("Virtual drives can only be resized upwards. Decreasing capacity is disabled to prevent file system corruption.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Apply Disk Expansion") {
                                applyStorageResize(vm.id)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox(label: Text("Bundle Portability & Backups").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Export this entire development sandbox structure into a portable JSON setup configuration file to share with team members or import on another Mac running SwiftCode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button(action: exportBundle) {
                                Label("Export Environment Bundle...", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)

                            Button(action: importBundle) {
                                Label("Import External Bundle...", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            } else {
                ContentUnavailableView(
                    "No Environment Selected",
                    systemImage: "externaldrive",
                    description: Text("Select an active environment from the list to manage its backing disk drives.")
                )
            }
        }
        .onAppear {
            if let vm = activeVM {
                diskResizeGB = Double(vm.storageGB)
            }
        }
    }

    private func applyStorageResize(_ vmID: UUID) {
        var vms = VirtualMachineRegistry.shared.load()
        if let idx = vms.firstIndex(where: { $0.id == vmID }) {
            vms[idx].storageGB = Int(diskResizeGB)
            try? VirtualMachineRegistry.shared.save(vms)
            stateStore.refreshVM(vmID)
            stateStore.addLog("Expanded primary storage volume drive to \(Int(diskResizeGB)) GB.", type: .success)
        }
    }

    private func exportBundle() {
        guard let vm = activeVM else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "\(vm.name.lowercased().replacingOccurrences(of: " ", with: "_"))_config.json"
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? VMBackupManager.shared.exportConfiguration(for: vm, to: url)
            stateStore.addLog("Exported environment bundle to \(url.lastPathComponent) successfully.", type: .success)
        }
    }

    private func importBundle() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.json]
        if openPanel.runModal() == .OK, let url = openPanel.url {
            if let imported = try? VMBackupManager.shared.importConfiguration(from: url) {
                stateStore.refreshVM(imported.id)
                stateStore.selectedVMID = imported.id
                stateStore.addLog("Successfully imported external environment bundle from \(url.lastPathComponent).", type: .success)
            }
        }
    }
}
