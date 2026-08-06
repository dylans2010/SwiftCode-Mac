import SwiftUI
#if canImport(Virtualization)
import Virtualization
#endif

public struct VirtualMachineTerminalView: View {
    public let vmID: UUID

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var terminalInput: String = ""
    @State private var capturesKeyboard = true
    @State private var isFullscreen = false
    @State private var scale: CGFloat = 1.0
    @State private var terminalHistory: [String] = [
        "Welcome to SwiftCode Virtualization Command Console.",
        "ubuntu@dev-workspace:~$ "
    ]

    #if canImport(Virtualization)
    @State private var realVM: VZVirtualMachine? = nil
    #endif

    public init(vmID: UUID) {
        self.vmID = vmID
    }

    private var vm: VirtualMachine? {
        stateStore.virtualMachines.first { $0.id == vmID }
    }

    private var controller: VirtualMachineController {
        VirtualMachineController(vmID: vmID)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // High-fidelity Virtual Machine Interactive Toolbar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm?.name ?? "Virtual Machine Console")
                        .font(.headline)
                    Text("Direct Hardware Display Stream")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Active Session VM Lifecycle Controllers
                HStack(spacing: 8) {
                    if vm?.status != .running {
                        Button {
                            Task {
                                await controller.start()
                                refreshRealVM()
                            }
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .tint(.green)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            Task {
                                await controller.pause()
                            }
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task {
                                await controller.stop()
                                refreshRealVM()
                            }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }

                    Menu {
                        Button("Restart Guest OS") {
                            Task {
                                await controller.restart()
                                refreshRealVM()
                            }
                        }
                        Button("Graceful Shutdown") {
                            Task {
                                await controller.shutdown()
                                refreshRealVM()
                            }
                        }
                        Button("Force Shutdown", role: .destructive) {
                            Task {
                                #if canImport(Virtualization)
                                try? await VirtualizationService.shared.stopVM(id: vmID, force: true)
                                #endif
                                stateStore.updateVMStatus(vmID, to: .stopped)
                                refreshRealVM()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
                .controlSize(.small)
            }

            // Real Virtualization Graphics View / Shell Wrapper
            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    // Title/Header (Terminal Style)
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Circle().fill(Color.yellow).frame(width: 8, height: 8)
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                        }
                        Spacer()
                        Text(vm?.status == .running ? "macOS Virtualization.framework display (Active)" : "Offline Display Terminal")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()

                        // Fullscreen / Scale Controls
                        HStack(spacing: 12) {
                            Button {
                                capturesKeyboard.toggle()
                            } label: {
                                Label("Capture Keys", systemImage: capturesKeyboard ? "keyboard.fill" : "keyboard")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)

                            Button {
                                isFullscreen.toggle()
                            } label: {
                                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            }
                            .buttonStyle(.plain)
                            .help("Toggle Fullscreen")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.12))

                    // Rendering Area: Real Apple Virtualization Graphics View if running, else Fallback Mock Shell
                    ZStack {
                        #if canImport(Virtualization)
                        if let activeVM = realVM, vm?.status == .running {
                            VZVirtualMachineViewRepresentable(virtualMachine: activeVM, capturesKeyboard: capturesKeyboard)
                                .scaleEffect(scale)
                                .frame(maxWidth: .infinity)
                                .frame(height: isFullscreen ? 500 : 300)
                                .background(Color.black)
                        } else {
                            fallbackShellView
                        }
                        #else
                        fallbackShellView
                        #endif
                    }
                }
                .cornerRadius(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Hardware Telemetry HUD Bar
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STATUS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor(vm?.status ?? .stopped))
                            .frame(width: 8, height: 8)
                        Text(vm?.status.rawValue.uppercased() ?? "OFFLINE")
                            .font(.caption.bold())
                    }
                }
                Divider().frame(height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU CORES")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(vm?.cpuCores ?? 2) Cores")
                        .font(.caption.bold())
                }
                Divider().frame(height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MEMORY ALLOCATED")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f GB", Double(vm?.memoryMB ?? 2048) / 1024.0))
                        .font(.caption.bold())
                }

                Spacer()

                HStack {
                    Text("Zoom:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $scale, in: 0.5...2.0)
                        .frame(width: 80)
                }
            }
            .padding(.horizontal, 8)
        }
        .onAppear {
            refreshRealVM()
        }
    }

    @ViewBuilder
    private var fallbackShellView: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .frame(height: isFullscreen ? 500 : 300)
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
    }

    private func refreshRealVM() {
        #if canImport(Virtualization)
        self.realVM = VirtualizationService.shared.getActiveVM(for: vmID)
        #endif
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
""")
            case "uname -a":
                terminalHistory.append("Linux dev-workspace 6.6.21-linuxkit #1 SMP PREEMPT_DYNAMIC ARM64 GNU/Linux")
            case "swift --version":
                terminalHistory.append("Swift version 6.0-dev (LLVM a8ef9bc1, Swift 28f9ac12)")
            case "df -h":
                terminalHistory.append("""
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda2        64G  4.2G   57G   7% /
""")
            default:
                terminalHistory.append("bash: command not found: \(cmd)")
            }
        }

        terminalHistory.append("ubuntu@dev-workspace:~$ ")
        terminalInput = ""
    }

    private func statusColor(_ status: VMStatus) -> Color {
        switch status {
        case .running: return .green
        case .starting: return .blue
        case .stopped: return .secondary
        case .pausing, .paused: return .orange
        case .stopping: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Native NSViewRepresentable for VZVirtualMachineView

#if canImport(Virtualization)
public struct VZVirtualMachineViewRepresentable: NSViewRepresentable {
    public let virtualMachine: VZVirtualMachine?
    public var capturesKeyboard: Bool

    public func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.virtualMachine = virtualMachine
        view.capturesSystemKeys = capturesKeyboard
        return view
    }

    public func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {
        nsView.virtualMachine = virtualMachine
        nsView.capturesSystemKeys = capturesKeyboard
    }
}
#endif
