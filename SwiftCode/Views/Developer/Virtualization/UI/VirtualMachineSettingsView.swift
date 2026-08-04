import SwiftUI

public struct VirtualMachineSettingsView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var cpuCores: Double = 2
    @State private var memoryGB: Double = 4
    @State private var storageGB: Double = 40
    @State private var name: String = ""
    @State private var showingAdvancedConfig = false

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    private var vm: VirtualMachine? {
        stateStore.virtualMachines.first { $0.id == vmID }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let activeVM = vm {
                // Section 1: General Settings
                GroupBox(label: Text("General Settings").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Environment Name")
                                    .fontWeight(.medium)
                                Text("Assign a descriptive local title for your development registry.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField("Environment Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 250)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 2: Performance Parameters
                GroupBox(label: Text("Performance Parameters").font(.headline)) {
                    VStack(alignment: .leading, spacing: 14) {
                        // CPU Cores Slider
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("CPU Core Allocation:", systemImage: "cpu")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(cpuCores)) Cores")
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                            }
                            Slider(value: $cpuCores, in: 1...16, step: 1)
                        }

                        Divider()

                        // Memory (RAM) Slider
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("Memory (RAM) Allocation:", systemImage: "memorychip")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.1f GB", memoryGB))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.purple)
                            }
                            Slider(value: $memoryGB, in: 1...64, step: 0.5)
                        }

                        Divider()

                        // Storage capacity info (Read-only resize is handled in StorageView)
                        HStack {
                            Label("Storage Capacity:", systemImage: "externaldrive")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(Int(storageGB)) GB (Locked)")
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                        }
                        Text("To expand backing disk capacity safely, navigate to the Storage & Sharing tab.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 3: Advanced Options (Hidden by default via Progressive Disclosure)
                DisclosureGroup(isExpanded: $showingAdvancedConfig) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Low-Level Hypervisor Configurations:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        SCDetailRow(label: "Target Kernel Boot Loader", value: "UEFI / GRUB Direct Boot")
                        SCDetailRow(label: "System Graphic Controller", value: "Apple Virtio-GPU (Accelerated)")
                        SCDetailRow(label: "Entropy Device (Randomness)", value: "Virtio-RNG (Hardware Entrusted)")
                        SCDetailRow(label: "Virtual Machine MAC Address", value: activeVM.macAddress)

                        Divider()
                            .padding(.vertical, 2)

                        Text("Note: Advanced hardware kernel configurations are handled dynamically by Apple's official Virtualization.framework APIs.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                    .padding(.top, 4)
                } label: {
                    Text("Show Advanced Technical Specifications...")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                HStack {
                    Spacer()
                    Button("Apply Resource Settings") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("No Environment selected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if let activeVM = vm {
                name = activeVM.name
                cpuCores = Double(activeVM.cpuCores)
                memoryGB = Double(activeVM.memoryMB) / 1024.0
                storageGB = Double(activeVM.storageGB)
            }
        }
    }

    private func saveSettings() {
        var vms = VirtualMachineRegistry.shared.load()
        if let idx = vms.firstIndex(where: { $0.id == vmID }) {
            vms[idx].name = name
            vms[idx].cpuCores = Int(cpuCores)
            vms[idx].memoryMB = Int(memoryGB * 1024)
            vms[idx].storageGB = Int(storageGB)
            try? VirtualMachineRegistry.shared.save(vms)
            stateStore.refreshVM(vmID)
            stateStore.addLog("Applied resource configurations for environment '\(name)'.", type: .success)
        }
    }
}
