import SwiftUI

public struct NSStashView: View {
    @State private var stashMessage = ""
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false
    @State private var localChanges: [LocalChange] = []

    public init() {}

    public struct LocalChange: Identifiable {
        public let id = UUID()
        public let path: String
        public let status: String // "M", "A", "D", "??", etc.
    }

    public var body: some View {
        Group {
            if let project = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Stash (⇧⌘Z)", systemImage: "archivebox.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text("Stash away local modifications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Optional stash message...", text: $stashMessage)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLoading)

                    // Local changes list section
                    Text("Local changes to stash:")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    VStack {
                        if localChanges.isEmpty {
                            Text("No local changes detected.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(localChanges) { change in
                                        HStack {
                                            Text(change.status)
                                                .font(.system(.caption2, design: .monospaced))
                                                .bold()
                                                .foregroundStyle(statusColor(for: change.status))
                                                .frame(width: 24, alignment: .leading)

                                            Text(change.path)
                                                .font(.caption2)
                                                .lineLimit(1)
                                                .truncationMode(.middle)

                                            Spacer()
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.05))
                                        .cornerRadius(4)
                                    }
                                }
                                .padding(2)
                            }
                        }
                    }
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .padding(4)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .padding(.vertical, 4)
                    }

                    if !successMsg.isEmpty {
                        Text(successMsg)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if !errorMsg.isEmpty {
                        NSGitErrorView(message: errorMsg)
                    }

                    Button("Stash Changes") {
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                let msg = stashMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                                var args = ["stash", "push"]
                                if !msg.isEmpty {
                                    args.append("-m")
                                    args.append(msg)
                                }
                                try await GitMenuBarCommandExecutor.runGit(args: args)
                                successMsg = "Local changes stashed cleanly."
                                stashMessage = ""
                                await loadLocalChanges(project: project)
                            } catch {
                                errorMsg = "Failed: \(error.localizedDescription)"
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoading)
                }
                .onAppear {
                    Task {
                        await loadLocalChanges(project: project)
                    }
                }
            } else {
                NoActiveProjectView(title: "Stash")
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func loadLocalChanges(project: Project) async {
        do {
            let output = try await GitMenuBarCommandExecutor.runGitCommand(
                arguments: ["status", "--porcelain"],
                workingDirectory: project.directoryURL
            )
            let lines = output.components(separatedBy: .newlines)
            var changes: [LocalChange] = []
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    let status = String(parts[0])
                    let path = String(parts[1])
                    changes.append(LocalChange(path: path, status: status))
                }
            }
            self.localChanges = changes
        } catch {
            self.localChanges = []
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status.trimmingCharacters(in: .whitespaces) {
        case "M": return .orange
        case "A": return .green
        case "D": return .red
        case "??": return .blue
        default: return .secondary
        }
    }
}
