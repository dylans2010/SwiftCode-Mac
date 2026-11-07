import YcodeIDECore
import YcodeSubprocess
import SwiftUI

@MainActor
public struct GitCLIView: View {
    public var repository: GitRepository
    public var aiCommandGenerator: ((String) async throws -> String)?

    @State private var customCommand = ""
    @State private var aiQuery = ""
    @State private var consoleOutput = ""
    @State private var isRunning = false
    @State private var selectedTheme: GitCLITheme = .system

    public init(repository: GitRepository, aiCommandGenerator: ((String) async throws -> String)? = nil) {
        self.repository = repository
        self.aiCommandGenerator = aiCommandGenerator
    }

    public static let presets: [(name: String, arguments: [String])] = [
        ("Status", ["status", "--short", "--branch"]),
        ("Recent commits", ["log", "--oneline", "-20"]),
        ("Branches", ["branch", "-a", "-v"]),
        ("Diff summary", ["diff", "--stat"]),
        ("Staged diff", ["diff", "--cached", "--stat"]),
        ("Remotes", ["remote", "-v"]),
        ("Stash list", ["stash", "list"]),
        ("Tags", ["tag", "--list"]),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Git Console", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Picker("Theme", selection: $selectedTheme) {
                    ForEach(GitCLITheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.name) { preset in
                        Button(preset.name) {
                            Task { await run(arguments: preset.arguments) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isRunning)
                    }
                }
            }

            HStack {
                Text("git")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("e.g. log --oneline -10", text: $customCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        Task { await runCustomCommand() }
                    }
                Button("Run") {
                    Task { await runCustomCommand() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(customCommand.trimmingCharacters(in: .whitespaces).isEmpty || isRunning)
            }

            HStack {
                TextField("Ask AI for a git command…", text: $aiQuery)
                    .textFieldStyle(.roundedBorder)
                    .disabled(aiCommandGenerator == nil)
                    .help(aiCommandGenerator == nil
                          ? "Ask AI is not wired up — pass aiCommandGenerator to enable it."
                          : "Describe what you want git to do.")
                Button("Ask AI") {
                    Task { await askAI() }
                }
                .buttonStyle(.bordered)
                .disabled(aiCommandGenerator == nil || aiQuery.trimmingCharacters(in: .whitespaces).isEmpty || isRunning)
            }

            ScrollView {
                Text(consoleOutput.isEmpty ? "Run a command to see its output here." : consoleOutput)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(selectedTheme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(selectedTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(minHeight: 180)

            if isRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
    }

    private func runCustomCommand() async {
        let parts = customCommand
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        await run(arguments: parts)
    }

    private func askAI() async {
        guard let aiCommandGenerator else { return }
        isRunning = true
        defer { isRunning = false }
        let query = aiQuery
        appendOutput("$ ask ai: \(query)\n")
        do {
            let command = try await aiCommandGenerator(query)
            let parts = command.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            guard !parts.isEmpty else {
                appendOutput("The assistant did not return a command.\n")
                return
            }
            customCommand = command
            await run(arguments: parts)
        } catch {
            appendOutput("Ask AI failed: \(error.localizedDescription)\n")
        }
    }

    private func run(arguments: [String]) async {
        isRunning = true
        defer { isRunning = false }
        appendOutput("$ git \(arguments.joined(separator: " "))\n")
        let gitPath = GitRepository.resolvedGitPath()
        let root = repository.root
        do {
            let output = try await Task.detached {
                try Subprocess.run(gitPath, arguments, currentDirectory: root)
            }.value
            if !output.stdoutText.isEmpty { appendOutput(output.stdoutText) }
            if !output.stderrText.isEmpty { appendOutput(output.stderrText) }
            if output.status != 0 {
                appendOutput("git exited with status \(output.status)\n")
            }
        } catch {
            appendOutput("Failed to run git: \(error.localizedDescription)\n")
        }
        appendOutput("\n")
    }

    private func appendOutput(_ text: String) {
        consoleOutput += text
    }

    public enum GitCLITheme: CaseIterable {
        case system
        case dark
        case light

        public var displayName: String {
            switch self {
            case .system: return "System"
            case .dark: return "Dark"
            case .light: return "Light"
            }
        }

        public var background: Color {
            switch self {
            case .system: return Color(nsColor: .textBackgroundColor)
            case .dark: return Color(red: 0.11, green: 0.11, blue: 0.12)
            case .light: return Color(red: 0.96, green: 0.96, blue: 0.96)
            }
        }

        public var foreground: Color {
            switch self {
            case .system: return .primary
            case .dark: return Color(red: 0.85, green: 0.85, blue: 0.86)
            case .light: return Color(red: 0.15, green: 0.15, blue: 0.16)
            }
        }
    }
}
