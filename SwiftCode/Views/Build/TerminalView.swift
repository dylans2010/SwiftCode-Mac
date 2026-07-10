import SwiftUI
import Combine

// MARK: - Terminal View

struct TerminalView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var commandInput = ""
    @State private var outputLines: [TerminalLine] = [
        TerminalLine(text: "SwiftCode Native Terminal v2.1", type: .info)
    ]
    @State private var commandHistory: [String] = []
    @State private var historyIndex = -1
    @State private var isRunning = false
    @State private var currentDirectory: String? = nil
    @FocusState private var inputFocused: Bool

    @State private var process: Process?
    @State private var outputPipe: Pipe?

    struct TerminalLine: Identifiable {
        let id = UUID()
        var text: String
        var type: LineType
        enum LineType { case command, output, error, info }
        var color: Color {
            switch type {
            case .command: return .cyan
            case .output:  return Color(red: 0.85, green: 0.85, blue: 0.85)
            case .error:   return .red
            case .info:    return .green
            }
        }
    }

    private var workingDirectoryURL: URL? {
        if let cwd = currentDirectory {
            return URL(fileURLWithPath: cwd)
        }
        return sessionStore.activeProject?.directoryURL
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider().opacity(0.3)
            outputArea
            Divider().opacity(0.3)
            inputBar
        }
        .background(Color(red: 0.06, green: 0.07, blue: 0.10))
        .onAppear {
            inputFocused = true
            if let dir = sessionStore.activeProject?.directoryURL {
                currentDirectory = dir.path
            }
        }
        .macDesktopOptimized()
    }

    // MARK: - Header

    private var terminalHeader: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 10, height: 10)
            Circle().fill(.yellow).frame(width: 10, height: 10)
            Circle().fill(.green).frame(width: 10, height: 10)
            Spacer()
            Text(promptPrefix)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                outputLines = [TerminalLine(text: "Cleared.", type: .info)]
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isRunning {
                Button {
                    process?.terminate()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.10, green: 0.10, blue: 0.14))
    }

    private var promptPrefix: String {
        workingDirectoryURL?.lastPathComponent ?? "Terminal"
    }

    // MARK: - Output Area

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(outputLines) { line in
                        HStack(alignment: .top, spacing: 4) {
                            if line.type == .command {
                                Text("❯")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                            Text(line.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(line.color)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .onChange(of: outputLines.count) {
                proxy.scrollTo("bottom")
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text("❯")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.cyan)

            TextField("", text: $commandInput)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white)
                .focused($inputFocused)
                .onSubmit { runCommand() }
                .onExitCommand {
                    // Handle ESC or similar if needed
                }
                .background(CommandHistoryHandler(commandInput: $commandInput, history: $commandHistory, historyIndex: $historyIndex))

            if isRunning {
                ProgressView().scaleEffect(0.5).tint(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
    }

    private func runCommand() {
        let cmd = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }

        outputLines.append(TerminalLine(text: cmd, type: .command))
        commandHistory.append(cmd)
        historyIndex = -1
        commandInput = ""

        if cmd == "clear" {
            outputLines = []
            return
        }

        executeNativeCommand(cmd)
    }

    private func executeNativeCommand(_ cmd: String) {
        isRunning = true

        let newProcess = Process()
        let pipe = Pipe()

        newProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        newProcess.arguments = ["-c", cmd]
        newProcess.currentDirectoryURL = workingDirectoryURL
        newProcess.standardOutput = pipe
        newProcess.standardError = pipe

        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.addOutput(output, type: .output)
                    }
                }
            }
        }

        newProcess.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.isRunning = false
                self.process = nil
                fileHandle.readabilityHandler = nil
            }
        }

        self.process = newProcess

        do {
            try newProcess.run()
        } catch {
            addOutput("Failed to run command: \(error.localizedDescription)", type: .error)
            isRunning = false
        }
    }

    private func addOutput(_ text: String, type: TerminalLine.LineType) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            outputLines.append(TerminalLine(text: line, type: type))
        }
    }
}

// MARK: - Command History Helper

struct CommandHistoryHandler: NSViewRepresentable {
    @Binding var commandInput: String
    @Binding var history: [String]
    @Binding var historyIndex: Int

    class Coordinator: NSObject {
        var parent: CommandHistoryHandler
        var monitor: Any?
        init(_ parent: CommandHistoryHandler) { self.parent = parent }

        func setupMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 126 { // Up arrow
                    if self.parent.historyIndex < self.parent.history.count - 1 {
                        self.parent.historyIndex += 1
                        self.parent.commandInput = self.parent.history[self.parent.history.count - 1 - self.parent.historyIndex]
                    }
                } else if event.keyCode == 125 { // Down arrow
                    if self.parent.historyIndex > 0 {
                        self.parent.historyIndex -= 1
                        self.parent.commandInput = self.parent.history[self.parent.history.count - 1 - self.parent.historyIndex]
                    } else if self.parent.historyIndex == 0 {
                        self.parent.historyIndex = -1
                        self.parent.commandInput = ""
                    }
                }
                return event
            }
        }

        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSView {
        context.coordinator.setupMonitor()
        return NSView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
            coordinator.monitor = nil
        }
    }
}
