import SwiftUI
import Combine

// MARK: - Terminal Themes

enum TerminalTheme: String, CaseIterable, Identifiable {
    case midnight = "Midnight Blue"
    case monokai = "Monokai Classic"
    case matrix = "Matrix Green"
    case chalkboard = "Chalkboard Gray"
    case solarized = "Solarized Dark"

    var id: String { rawValue }

    var backgroundColor: Color {
        switch self {
        case .midnight: return Color(red: 0.06, green: 0.07, blue: 0.10)
        case .monokai: return Color(red: 0.11, green: 0.11, blue: 0.11)
        case .matrix: return .black
        case .chalkboard: return Color(red: 0.18, green: 0.20, blue: 0.22)
        case .solarized: return Color(red: 0.03, green: 0.15, blue: 0.21)
        }
    }

    var textColor: Color {
        switch self {
        case .matrix: return .green
        default: return Color(red: 0.85, green: 0.85, blue: 0.85)
        }
    }

    var headerColor: Color {
        switch self {
        case .midnight: return Color(red: 0.10, green: 0.10, blue: 0.14)
        case .monokai: return Color(red: 0.16, green: 0.16, blue: 0.16)
        case .matrix: return Color(red: 0.08, green: 0.08, blue: 0.08)
        case .chalkboard: return Color(red: 0.24, green: 0.26, blue: 0.28)
        case .solarized: return Color(red: 0.04, green: 0.19, blue: 0.26)
        }
    }
}

// MARK: - Presets Model

struct TerminalPreset: Identifiable {
    let id = UUID()
    let name: String
    let command: String
    let icon: String
}

// MARK: - Terminal View

struct TerminalView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var commandInput = ""
    @State private var outputLines: [TerminalLine] = [
        TerminalLine(text: "SwiftCode Native Terminal v2.2", type: .info)
    ]
    @State private var commandHistory: [String] = []
    @State private var historyIndex = -1
    @State private var isRunning = false
    @State private var currentDirectory: String? = nil
    @FocusState private var inputFocused: Bool

    @State private var process: Process?
    @State private var outputPipe: Pipe?

    // Custom Themes & Presets
    @State private var selectedTheme: TerminalTheme = .midnight
    @State private var showPresetsPopover = false

    // Ask AI States
    @State private var isShowingAIPopover = false
    @State private var aiQuery = ""
    @State private var aiResponse = ""
    @State private var isAILoading = false

    struct TerminalLine: Identifiable {
        let id = UUID()
        var text: String
        var type: LineType
        enum LineType { case command, output, error, info }
    }

    private let presets: [TerminalPreset] = [
        TerminalPreset(name: "Compile App", command: "swift build", icon: "hammer.fill"),
        TerminalPreset(name: "Archive App", command: "xcodebuild -project SwiftCode.xcodeproj -scheme SwiftCode -configuration Release archive", icon: "archivebox.fill"),
        TerminalPreset(name: "Run Tests", command: "swift test", icon: "play.fill"),
        TerminalPreset(name: "Clean Build", command: "swift package clean", icon: "trash.fill"),
        TerminalPreset(name: "Swift Version", command: "swift --version", icon: "info.circle.fill"),
        TerminalPreset(name: "List Directory", command: "ls -la", icon: "folder.fill"),
        TerminalPreset(name: "System Diagnostics", command: "uname -a && df -h", icon: "cpu")
    ]

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
        .background(selectedTheme.backgroundColor)
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
        HStack(spacing: 12) {
            Circle().fill(.red).frame(width: 10, height: 10)
            Circle().fill(.yellow).frame(width: 10, height: 10)
            Circle().fill(.green).frame(width: 10, height: 10)

            Spacer()

            // Directory / Prefix info
            Text(promptPrefix)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Ask AI Button
            Button {
                isShowingAIPopover = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text("Ask AI")
                        .font(.caption)
                }
                .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingAIPopover, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ask AI Prompt Generator")
                        .font(.headline)
                        .foregroundStyle(.cyan)

                    Text("Describe what you'd like to do in plain English. The AI will output the full bash prompt with explanatory comments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("e.g. Find all .swift files and count lines of code", text: $aiQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)

                    if isAILoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Generating bash prompt...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !aiResponse.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Generated Command:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            ScrollView {
                                Text(aiResponse)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.green)
                                    .padding(8)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(6)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 120)

                            HStack(spacing: 8) {
                                Button("Run in Terminal") {
                                    isShowingAIPopover = false
                                    commandInput = extractCommandFromResponse(aiResponse)
                                    runCommand()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)

                                Button("Copy") {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(aiResponse, forType: .string)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Generate") {
                            generateAICommand()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(aiQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAILoading)
                    }
                }
                .padding()
                .frame(width: 350)
            }

            // Theme Selector
            Picker("", selection: $selectedTheme) {
                ForEach(TerminalTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .controlSize(.small)

            // Clear Button
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
        .background(selectedTheme.headerColor)
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
                                    .foregroundStyle(selectedTheme == .matrix ? .green : .cyan)
                            }
                            Text(line.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(color(for: line.type))
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

    private func color(for type: TerminalLine.LineType) -> Color {
        switch type {
        case .command:
            return selectedTheme == .matrix ? .green : .cyan
        case .output:
            return selectedTheme.textColor
        case .error:
            return .red
        case .info:
            return selectedTheme == .matrix ? .green : .green
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text("❯")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(selectedTheme == .matrix ? .green : .cyan)

            TextField("", text: $commandInput)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(selectedTheme.textColor)
                .focused($inputFocused)
                .onSubmit { runCommand() }
                .onExitCommand {
                    // Handle ESC or similar if needed
                }
                .background(CommandHistoryHandler(commandInput: $commandInput, history: $commandHistory, historyIndex: $historyIndex))

            // Blue Chevron for Preset Options Tooltip
            Button {
                showPresetsPopover = true
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPresetsPopover, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Preset Options")
                        .font(.headline)
                        .padding(.bottom, 2)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(presets) { preset in
                                Button {
                                    showPresetsPopover = false
                                    runPreset(preset.command)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: preset.icon)
                                            .font(.title3)
                                            .foregroundStyle(.blue)
                                            .frame(width: 24, height: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(preset.name)
                                                .font(.body)
                                                .fontWeight(.medium)
                                            Text(preset.command)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .padding()
                .frame(width: 320)
            }

            if isRunning {
                ProgressView().scaleEffect(0.5).tint(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(selectedTheme.headerColor)
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

    private func runPreset(_ cmd: String) {
        outputLines.append(TerminalLine(text: cmd, type: .command))
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

    // MARK: - Ask AI Generation

    private func generateAICommand() {
        let query = aiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isAILoading = true
        aiResponse = ""

        let systemPrompt = """
        You are a systems terminal expert assistant. The user wants to write a shell command or script for their Mac.
        Given their plain English request, output ONLY the functional bash/zsh command or script block.
        You MUST include clear, detailed inline comments starting with '#' right above the command or script to explain exactly what that bash command would do.
        Avoid returning extra conversational pleasantries. Output ONLY the comments and the shell commands.
        """

        let messages = [
            AIMessage(role: .user, content: query)
        ]

        let model = AppSettings.shared.selectedModel.isEmpty ? "meta-llama/llama-3-70b-instruct" : AppSettings.shared.selectedModel

        Task {
            do {
                try await OpenRouterService.shared.streamChat(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt
                ) { token in
                    await MainActor.run {
                        aiResponse += token
                    }
                }
                await MainActor.run {
                    isAILoading = false
                }
            } catch {
                await MainActor.run {
                    aiResponse = "Error: \(error.localizedDescription)"
                    isAILoading = false
                }
            }
        }
    }

    private func extractCommandFromResponse(_ raw: String) -> String {
        var lines = raw.components(separatedBy: .newlines)
        // Strip markdown backticks if present
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.hasPrefix("```")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
