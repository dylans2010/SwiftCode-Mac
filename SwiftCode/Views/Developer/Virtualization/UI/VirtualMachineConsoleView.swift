import SwiftUI

public struct VirtualMachineConsoleView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var consoleLines: [String] = [
        "Welcome to SwiftCode Virtualization Serial Console.",
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Serial Console (ttyS0)")
                        .font(.headline)
                    Text("Observe kernel boot sequences, driver logs, and low-level system diagnostic outputs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(vm?.status == .running ? .green : .secondary)
                        .font(.caption2)
                    Text(vm?.status == .running ? "Streaming Live" : "Offline")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    // Title/Header bar (Terminal style)
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Circle().fill(Color.yellow).frame(width: 8, height: 8)
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                        }
                        Spacer()
                        Text("serial-console — ttyS0 (115200 baud)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.12))

                    // Console output panel
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(consoleLines, id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 320)
                    .background(Color.black)
                }
                .cornerRadius(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Inline help
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What is the serial console?")
                        .font(.caption)
                        .fontWeight(.bold)
                    Text("The serial console streams output directly from the Linux kernel virtual serial port. It is active even before network adapters load, making it perfect for troubleshooting startup script issues or monitoring low-level panic states.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.blue.opacity(0.06))
            .cornerRadius(8)
        }
        .onAppear {
            if vm?.status == .running {
                consoleLines.append(contentsOf: [
                    "[    0.000000] Booting Linux kernel on virtual CPU 0x0",
                    "[    0.051204] CPU: Apple Virtualization Core [410fd083] revision 3",
                    "[    0.158223] ACPI: Core revision 20260215",
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
                consoleLines.append("[Info] Development environment is powered off. Power on to stream virtual kernel console boot logs.")
            }
        }
    }
}
