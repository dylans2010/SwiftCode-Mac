import SwiftUI

public struct NSApplyStashView: View {
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false
    @State private var stashedChanges: [StashedChange] = []

    public init() {}

    public struct StashedChange: Identifiable {
        public let id = UUID()
        public let path: String
        public let status: String // "M", "A", "D", etc.
    }

    public var body: some View {
        Group {
            if let project = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Apply Stash (⇧⌘V)", systemImage: "archivebox.fill")
                        .font(.headline)
                        .foregroundStyle(.green)

                    Text("Apply the most recent stashed state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Stashed changes list section
                    Text("Files in latest stash:")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    VStack {
                        if stashedChanges.isEmpty {
                            Text("No stashed changes found.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(stashedChanges) { change in
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

                    Button("Apply Last Stash") {
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                try await GitMenuBarCommandExecutor.runGit(args: ["stash", "apply"])
                                successMsg = "Successfully applied stashed modifications."
                                await loadStashedChanges(project: project)
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
                        await loadStashedChanges(project: project)
                    }
                }
            } else {
                NoActiveProjectView(title: "Apply Stash")
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func loadStashedChanges(project: Project) async {
        do {
            let output = try await GitMenuBarCommandExecutor.runGitCommand(
                arguments: ["stash", "show", "--name-status"],
                workingDirectory: project.directoryURL
            )
            let lines = output.components(separatedBy: .newlines)
            var changes: [StashedChange] = []
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                // Name-status output can be delimited by spaces or tab, e.g.:
                // M\tpath/to/file or M path/to/file
                let parts = trimmed.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    let status = String(parts[0])
                    let path = String(parts[1])
                    changes.append(StashedChange(path: path, status: status))
                } else {
                    let spaceParts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    if spaceParts.count >= 2 {
                        let status = String(spaceParts[0])
                        let path = String(spaceParts[1])
                        changes.append(StashedChange(path: path, status: status))
                    }
                }
            }
            self.stashedChanges = changes
        } catch {
            self.stashedChanges = []
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status.trimmingCharacters(in: .whitespaces) {
        case "M": return .orange
        case "A": return .green
        case "D": return .red
        default: return .secondary
        }
    }
}
