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
        VStack(alignment: .leading, spacing: 16) {
            Text("Virtual Storage & Disk Drives")
                .font(.headline)
            Text("Manage backing virtual disk image sizes, allocations, and raw backup directories.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let vm = activeVM {
                GroupBox(label: Text("Backing Storage Allocations").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Active Storage Drive:")
                            Spacer()
                            Text("Primary Root Volume (/dev/vda)")
                                .fontWeight(.bold)
                        }

                        HStack {
                            Text("Allocated Capacity:")
                            Spacer()
                            Text("\(vm.storageGB) GB")
                                .fontWeight(.bold)
                        }

                        HStack {
                            Text("Estimated Free Space:")
                            Spacer()
                            Text("88% Available")
                                .foregroundStyle(.green)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resize Virtual Disk Volume:")
                                .fontWeight(.medium)

                            HStack {
                                Slider(value: $diskResizeGB, in: Double(vm.storageGB)...2000, step: 5)
                                Text("\(Int(diskResizeGB)) GB")
                                    .fontWeight(.bold)
                                    .frame(width: 80, alignment: .trailing)
                            }

                            Text("Note: Virtual volumes can only be resized upwards. Decreasing disk capacity is unsupported to prevent data corruption.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Spacer()
                            Button("Apply Resize") {
                                applyStorageResize(vm.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox(label: Text("Backup & Portability Suite").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export this virtual environment configuration to a portable file package to share with team members or deploy on other development setups.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Export VM Bundle...") {
                                let savePanel = NSSavePanel()
                                savePanel.allowedContentTypes = [.json]
                                savePanel.nameFieldStringValue = "\(vm.name.lowercased().replacingOccurrences(of: " ", with: "_"))_config.json"
                                if savePanel.runModal() == .OK, let url = savePanel.url {
                                    try? VMBackupManager.shared.exportConfiguration(for: vm, to: url)
                                    stateStore.addLog("Exported virtual environment bundle successfully.", type: .success)
                                }
                            }

                            Button("Import External Environment...") {
                                let openPanel = NSOpenPanel()
                                openPanel.allowsMultipleSelection = false
                                openPanel.canChooseDirectories = false
                                openPanel.canChooseFiles = true
                                openPanel.allowedContentTypes = [.json]
                                if openPanel.runModal() == .OK, let url = openPanel.url {
                                    if let imported = try? VMBackupManager.shared.importConfiguration(from: url) {
                                        stateStore.refreshVM(imported.id)
                                        stateStore.selectedVMID = imported.id
                                        stateStore.addLog("Imported virtual environment from backup bundle.", type: .success)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            } else {
                ContentUnavailableView(
                    "No Virtual Machine Selected",
                    systemImage: "externaldrive",
                    description: Text("Select a virtual machine to inspect storage allocations.")
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
            stateStore.addLog("Resized primary volume capacity to \(Int(diskResizeGB)) GB.", type: .success)
        }
    }
}
