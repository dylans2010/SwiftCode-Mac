import SwiftUI

public struct VirtualMachineTerminalView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var terminalInput: String = ""
    @State private var terminalHistory: [String] = [
        "Welcome to SwiftCode VM Embedded Shell.",
        "ubuntu@dev-workspace:~$ "
    ]

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    private var vm: VirtualMachine? {
        stateStore.virtualMachines.first { $0.id == vmID }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Interactive Guest Terminal")
                .font(.headline)
            Text("Open standard SSH or serial shell sessions inside the guest operating system environment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    // Header controls
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundStyle(.blue)
                        Text("bash — ubuntu@dev-workspace")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Clear Terminal") {
                            terminalHistory = ["ubuntu@dev-workspace:~$ "]
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))

                    // Display list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(terminalHistory, id: \.self) { line in
                                Text(line)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 300)
                    .background(Color.black)

                    // Terminal Input Row
                    HStack(spacing: 8) {
                        Text("ubuntu@dev-workspace:~$")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.green)

                        TextField("", text: $terminalInput, onCommit: executeCommand)
                            .textFieldStyle(.plain)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.95))
                }
                .cornerRadius(6)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    private func executeCommand() {
        let cmd = terminalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }

        terminalHistory.append("ubuntu@dev-workspace:~$ \(cmd)")

        // Simulating standard shell inputs
        if vm?.status != .running {
            terminalHistory.append("Error: Virtual machine is stopped. Cannot send commands.")
        } else {
            switch cmd.lowercased() {
            case "help":
                terminalHistory.append("""
Available commands:
  help           Show this assistance list
  uname -a       Print kernel information
  swift --version Show Swift compiler version
  df -h          Display storage utilization
  top            Render active processes
""")
            case "uname -a":
                terminalHistory.append("Linux dev-workspace 6.6.21-linuxkit #1 SMP PREEMPT_DYNAMIC ARM64 GNU/Linux")
            case "swift --version":
                terminalHistory.append("Swift version 6.0-dev (LLVM a8ef9bc1, Swift 28f9ac12)")
            case "df -h":
                terminalHistory.append("""
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda2        64G  4.2G   57G   7% /
tmpfs           4.0G     0  4.0G   0% /dev/shm
""")
            case "top":
                terminalHistory.append("""
PID   USER     PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
 154  root     20   0   14.2g  88.4m  14.2m S   1.2   1.1   0:04.12 swiftc
 302  ubuntu   20   0   40560   4.2m   2.1m R   0.5   0.1   0:00.41 top
   1  root     20   0    2311   1.1m   0.8m S   0.0   0.0   0:01.04 systemd
""")
            default:
                terminalHistory.append("bash: command not found: \(cmd)")
            }
        }

        terminalHistory.append("ubuntu@dev-workspace:~$ ")
        terminalInput = ""
    }
}
