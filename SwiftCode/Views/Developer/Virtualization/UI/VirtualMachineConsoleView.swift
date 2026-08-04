import SwiftUI

public struct VirtualMachineConsoleView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var consoleLines: [String] = [
        "Welcome to SCVirtualizationKit Serial Console.",
        "Connecting to serial port ttyS0...",
        "Virtual graphic engine ready."
    ]

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    private var vm: VirtualMachine? {
        stateStore.virtualMachines.first { $0.id == vmID }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Virtual Machine Live GPU / Serial Console Screen")
                .font(.headline)
            Text("Observe kernel boot sequences, device diagnostics, and display output.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    // Title/Header bar
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(vm?.status == .running ? .green : .secondary)
                        Text(vm?.name ?? "Console")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("ttyS0 (115200 baud)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))

                    // Console output panel
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(consoleLines, id: \.self) { line in
                                Text(line)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 320)
                    .background(Color.black)
                }
                .cornerRadius(6)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .onAppear {
            if vm?.status == .running {
                consoleLines.append(contentsOf: [
                    "[    0.000000] Booting Linux kernel on physical CPU 0x0",
                    "[    0.051204] CPU: ARMv8 Processor [410fd083] revision 3",
                    "[    0.158223] ACPI: Core revision 20230628",
                    "[    0.503921] SCSI subsystem initialized",
                    "[    0.803401] libata version 3.00 loaded.",
                    "[    1.109382] EXT4-fs (vda2): mounted filesystem with ordered data mode. Opts: (null)",
                    "systemd[1]: Started Dispatch Password Requests to Console Directory.",
                    "systemd[1]: Reached target Local File Systems.",
                    "systemd[1]: Reached target System Initialization.",
                    "systemd[1]: Started SSH Key Generation.",
                    "systemd[1]: Reached target Multi-User System.",
                    "",
                    "Ubuntu 24.04 LTS ubuntu ttyS0",
                    "ubuntu login: "
                ])
            } else {
                consoleLines.append("Machine is currently powered off. Start the VM to stream serial boot logs.")
            }
        }
    }
}
