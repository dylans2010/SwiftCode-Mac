import SwiftUI

struct GitCLIView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @State private var commandPreset = "status"
    @State private var customArgs = ""
    @State private var output = "Welcome to Git CLI.\nChoose a preset command or enter custom arguments below."
    @State private var isRunning = false

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Preset Command Panel
                VStack(alignment: .leading, spacing: 10) {
                    Text("Preset Git Commands")
                        .font(.headline)
                        .foregroundColor(.secondary)

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
                                        .background(commandPreset == preset ? Color.orange.opacity(0.2) : Color.white.opacity(0.05), in: Capsule())
                                        .foregroundStyle(commandPreset == preset ? .orange : .primary)
                                        .overlay(Capsule().stroke(commandPreset == preset ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                // Custom options & Custom execution
                HStack(spacing: 12) {
                    Text("git")
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.2), in: Capsule())
                        .foregroundColor(.green)

                    TextField("Type options e.g. status --short, checkout main...", text: $customArgs)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            runCustomCommand()
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
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                // Console Output
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding()
                }
                .background(Color.black)

                Divider()

                // Console Control Toolbar
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
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .navigationTitle("Git CLI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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
}
