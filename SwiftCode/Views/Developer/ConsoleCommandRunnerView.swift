import SwiftUI

struct ConsoleCommandRunnerView: View {
    @State private var commandInput: String = ""
    @State private var output: String = "SwiftCode Console v1.0\nType 'help' for commands."

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(output)
                    .font(.system(.subheadline, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .liquidGlass(style: .hud, cornerRadius: 0)
            .foregroundStyle(.green)

            HStack {
                Text(">").foregroundStyle(.secondary)
                TextField("Command...", text: $commandInput)
                    .onSubmit { runCommand() }
                    .autocorrectionDisabled()
#if os(iOS)
#endif
            }
            .padding()
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
        }
        .navigationTitle("Console Runner")
    }

    private func runCommand() {
        let cmd = commandInput.trimmingCharacters(in: .whitespaces)
        output += "\n> \(cmd)"

        switch cmd {
        case "help":
            output += "\nAvailable commands: help, ls, clear, whoami, ping"
        case "ls":
            output += "\nDocuments/  Library/  tmp/"
        case "clear":
            output = "Console cleared."
        case "whoami":
            output += "\n\(Host.current().localizedName ?? "macOS Device")"
        case "ping":
            output += "\n64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.042 ms"
        default:
            output += "\nUnknown command: \(cmd)"
        }
        commandInput = ""
    }
}
