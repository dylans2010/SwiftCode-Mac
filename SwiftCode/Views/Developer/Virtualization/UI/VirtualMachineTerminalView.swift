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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interactive Command Shell")
                        .font(.headline)
                    Text("Open secure shell (SSH) sessions inside the guest workspace.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button(action: clearTerminal) {
                    Label("Clear Terminal", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    // Header controls (Terminal style)
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Circle().fill(Color.yellow).frame(width: 8, height: 8)
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                        }
                        Spacer()
                        Text("bash — ubuntu@dev-workspace — SSH")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.12))

                    // Display list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(terminalHistory, id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 260)
                    .background(Color.black)

                    // Terminal Input Row
                    HStack(spacing: 6) {
                        Text("ubuntu@dev-workspace:~$")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green)

                        TextField("", text: $terminalInput, onCommit: executeCommand)
                            .textFieldStyle(.plain)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.95))
                }
                .cornerRadius(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Quick helper commands
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested Commands:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    suggestedButton("help", desc: "Show active helpers")
                    suggestedButton("uname -a", desc: "Print kernel core details")
                    suggestedButton("swift --version", desc: "Check compiler tools")
                    suggestedButton("df -h", desc: "Check disk sectors")
                }
            }
        }
    }

    @ViewBuilder
    private func suggestedButton(_ command: String, desc: String) -> some View {
        Button {
            terminalInput = command
            executeCommand()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(command)
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                Text(desc)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func clearTerminal() {
        terminalHistory = ["ubuntu@dev-workspace:~$ "]
    }

    private func executeCommand() {
        let cmd = terminalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }

        terminalHistory.append("ubuntu@dev-workspace:~$ \(cmd)")

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
