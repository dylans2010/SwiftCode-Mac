import SwiftUI

public struct VirtualMachineSettingsView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var cpuCores: Double = 2
    @State private var memoryGB: Double = 4
    @State private var storageGB: Double = 40
    @State private var name: String = ""

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    private var vm: VirtualMachine? {
        stateStore.virtualMachines.first { $0.id == vmID }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let activeVM = vm {
                GroupBox(label: Text("General Settings").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Name:")
                                .fontWeight(.medium)
                            Spacer()
                            TextField("Environment Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 250)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox(label: Text("Hardware Configurations").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("CPU Cores:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(Int(cpuCores)) Cores")
                                .fontWeight(.bold)
                        }
                        Slider(value: $cpuCores, in: 1...16, step: 1)

                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            Text("Memory (RAM):")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f GB", memoryGB))
                                .fontWeight(.bold)
                        }
                        Slider(value: $memoryGB, in: 1...64, step: 0.5)

                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            Text("Virtual Disk Storage:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(Int(storageGB)) GB")
                                .fontWeight(.bold)
                        }
                        Slider(value: $storageGB, in: 10...1000, step: 5)
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                HStack {
                    Spacer()
                    Button("Apply Hardware Settings") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("No Virtual Machine selected.")
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
            stateStore.addLog("Applied updated hardware config for \(name).", type: .success)
        }
    }
}
