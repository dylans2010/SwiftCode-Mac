import SwiftUI

struct LLDBCommandItem: Identifiable {
    let id = UUID()
    let name: String
    let usage: String
    let explanation: String
}

public struct LLDBDebuggerCheatsheetView: View {
    private let commands = [
        LLDBCommandItem(name: "po (print object)", usage: "po self.view", explanation: "Evaluate and print the description of a target variable, class instance, or standard object properties recursively."),
        LLDBCommandItem(name: "p (expression)", usage: "p count + 5", explanation: "Evaluate expression and print the raw, low-level result description directly in terminal console."),
        LLDBCommandItem(name: "v (frame variable)", usage: "v userDetails", explanation: "Inspect standard variables in the active frame without executing any compiled code on active CPU registers."),
        LLDBCommandItem(name: "expression", usage: "expr self.title = \"Test\"", explanation: "Dynamically modify active in-memory parameters and variables at runtime execution break lines."),
        LLDBCommandItem(name: "bt (backtrace)", usage: "bt", explanation: "Print all active stacks and frames in the current calling thread to debug cascade crash triggers."),
        LLDBCommandItem(name: "breakpoint list", usage: "br list", explanation: "List all active breakpoint markers and reference indices in the current active debugger session.")
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("LLDB Debugger Reference", systemImage: "ant")
                    .font(.title2.bold())
                Text("Command reference guide for interactive Xcode/terminal LLDB debugging environments.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)

            Divider()

            List {
                ForEach(commands) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.name)
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        Text(item.explanation)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Example: \(item.usage)")
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.18))
                            .cornerRadius(6)
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.inset)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
