import SwiftUI

struct GitCLIView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var commandPreset = "status"
    @State private var customArgs = ""
    @State private var output = "Welcome to Git CLI.\nChoose a preset command or enter custom arguments below."
    @State private var isRunning = false

    // Themes & Presets
    @State private var selectedTheme: TerminalTheme = .midnight
    @State private var showPresetsPopover = false

    // Ask AI States
    @State private var showAIPopover = false
    @State private var aiQuery = ""
    @State private var aiResponse = ""
    @State private var isAILoading = false

    private let presets = [
        "status",
        "log --oneline -n 10",
        "diff",
        "branch -a",
        "remote -v",
        "add .",
        "commit -m",
        "push",
        "pull"
    ]

    private let advancedPresets = [
        "stash save \"Work in progress\"",
        "stash pop",
        "reset --soft HEAD~1",
        "reset --hard",
        "commit --amend",
        "clean -fd",
        "fetch --all",
        "shortlog -sn"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Card 1: Preset Command Panel
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Preset Git Commands", systemImage: "terminal.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(presets, id: \.self) { preset in
                                        Button {
                                            commandPreset = preset
                                            runCommand(preset: preset)
                                        } label: {
                                            Text("git \(preset)")
                                                .font(.system(.body, design: .monospaced))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(commandPreset == preset ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1), in: Capsule())
                                                .foregroundStyle(commandPreset == preset ? .orange : .primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Custom Execute Command Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Custom Git Executor", systemImage: "terminal")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                Text("git")
                                    .font(.system(.body, design: .monospaced).weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.15), in: Capsule())
                                    .foregroundColor(.green)

                                TextField("Type options e.g. status --short, checkout main...", text: $customArgs)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .onSubmit {
                                        runCustomCommand()
                                    }

                                // Advanced Presets popover
                                Button {
                                    showPresetsPopover = true
                                } label: {
                                    Image(systemName: "chevron.right.circle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showPresetsPopover, arrowEdge: .top) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Advanced Presets")
                                            .font(.headline)

                                        ForEach(advancedPresets, id: \.self) { adv in
                                            Button {
                                                showPresetsPopover = false
                                                customArgs = adv
                                                executeGit(arguments: adv.split(separator: " ").map(String.init))
                                            } label: {
                                                HStack {
                                                    Image(systemName: "terminal.fill")
                                                        .foregroundStyle(.orange)
                                                    Text("git \(adv)")
                                                        .font(.system(.caption, design: .monospaced))
                                                }
                                                .padding(.vertical, 4)
                                            }
                                            .buttonStyle(.plain)
                                            Divider()
                                        }
                                    }
                                    .padding()
                                    .frame(width: 280)
                                }

                                Button {
                                    runCustomCommand()
                                } label: {
                                    if isRunning {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Text("Execute")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .disabled(isRunning)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: Console Terminal Output
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Console Terminal Output", systemImage: "text.alignleft")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                Spacer()
                            }

                            ScrollView {
                                Text(output)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(selectedTheme.textColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding()
                            }
                            .frame(height: 300)
                            .background(selectedTheme.backgroundColor)
                            .cornerRadius(8)

                            HStack {
                                Button("Clear Console") {
                                    output = "Console cleared."
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)

                                Spacer()

                                Button("Copy Output") {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(output, forType: .string)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.orange)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .navigationTitle("Git CLI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        // Ask AI Button
                        Button {
                            showAIPopover = true
                        } label: {
                            Label("Ask AI", systemImage: "sparkles")
                                .foregroundColor(.cyan)
                        }
                        .buttonStyle(.bordered)
                        .popover(isPresented: $showAIPopover, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Ask AI Git Command Generator")
                                    .font(.headline)
                                    .foregroundStyle(.cyan)

                                Text("Describe what you'd like to do with Git in plain English. The AI will output the full git prompt with explanatory comments.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                TextField("e.g. Undo last commit but keep changes", text: $aiQuery)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)

                                if isAILoading {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                        Text("Generating Git command...")
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
                                            Button("Run in Git CLI") {
                                                showAIPopover = false
                                                let cleaned = extractGitCommandFromResponse(aiResponse)
                                                customArgs = cleaned
                                                runCustomCommand()
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
                                        generateGitCommand()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(aiQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAILoading)
                                }
                            }
                            .padding()
                            .frame(width: 350)
                        }

                        Picker("Console Theme", selection: $selectedTheme) {
                            ForEach(TerminalTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func runCommand(preset: String) {
        let args = preset
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        executeGit(arguments: args)
    }

    private func runCustomCommand() {
        let trimmed = customArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let args = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        executeGit(arguments: args)
    }

    private func executeGit(arguments: [String]) {
        guard !arguments.isEmpty else { return }
        isRunning = true
        let cmdDisplay = "git " + arguments.joined(separator: " ")
        output.append("\n\n$ \(cmdDisplay)\n")

        Task {
            do {
                let gitBinary = settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: URL(fileURLWithPath: gitBinary),
                    arguments: arguments,
                    workingDirectory: project.directoryURL
                )

                await MainActor.run {
                    if !result.stdout.isEmpty {
                        output.append(result.stdout)
                    }
                    if !result.stderr.isEmpty {
                        output.append("\n" + result.stderr)
                    }
                    if result.exitCode != 0 {
                        output.append("\nProcess exited with status code \(result.exitCode)")
                    }
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    output.append("Error executing command: \(error.localizedDescription)\n")
                    isRunning = false
                }
            }
        }
    }

    // MARK: - Ask AI Generation

    private func generateGitCommand() {
        let query = aiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isAILoading = true
        aiResponse = ""

        let systemPrompt = """
        You are a Git version control expert. Given the user's plain English request, output ONLY the functional git command or list of git commands.
        You MUST include clear, detailed inline comments starting with '#' right above each command to explain exactly what that git command would do.
        Avoid returning extra conversational pleasantries. Output ONLY the comments and the git commands.
        """

        let messages = [
            AIMessage(role: .user, content: query)
        ]

        let model = settings.selectedModel.isEmpty ? "meta-llama/llama-3-70b-instruct" : settings.selectedModel

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

    private func extractGitCommandFromResponse(_ raw: String) -> String {
        var lines = raw.components(separatedBy: .newlines)
        // Strip markdown backticks if present
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.hasPrefix("```")
        }
        let nonCommentLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.hasPrefix("#") && !trimmed.isEmpty
        }
        let commandLine = nonCommentLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if commandLine.lowercased().hasPrefix("git ") {
            return String(commandLine.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return commandLine
    }
}
