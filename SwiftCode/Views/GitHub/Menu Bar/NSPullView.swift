import SwiftUI

public struct NSPullView: View {
    @State private var branches: [String] = ["main"]
    @State private var selectedBranch = "main"
    @State private var useRebase = false
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Pull (⇧⌘L)", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.cyan)

                    Text("Fetch and integrate remote changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Pull from Branch", selection: $selectedBranch) {
                        ForEach(branches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isLoading)

                    Toggle("Rebase local commits instead of merge", isOn: $useRebase)
                        .toggleStyle(.checkbox)
                        .disabled(isLoading)

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

                    HStack {
                        Button("Pull changes") {
                            Task {
                                isLoading = true
                                successMsg = ""
                                errorMsg = ""
                                do {
                                    var args = ["pull", "origin", selectedBranch]
                                    if useRebase {
                                        args.append("--rebase")
                                    }
                                    try await GitMenuBarCommandExecutor.runGit(args: args)
                                    successMsg = "Pulled changes from '\(selectedBranch)' successfully."
                                } catch {
                                    errorMsg = "Failed: \(error.localizedDescription)"
                                }
                                isLoading = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isLoading)

                        Button("Refresh Branches") {
                            Task {
                                await loadBranches()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isLoading)
                    }
                }
                .onAppear {
                    Task {
                        await loadBranches()
                    }
                }
            } else {
                NoActiveProjectView(title: "Pull")
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func loadBranches() async {
        isLoading = true
        let list = await GitMenuBarCommandExecutor.getBranchesList()
        branches = list.isEmpty ? ["main"] : list

        // Use current branch if it exists in the list, otherwise default to main (or first available)
        if let current = try? await GitMenuBarCommandExecutor.getCurrentBranchName(), list.contains(current) {
            selectedBranch = current
        } else if list.contains("main") {
            selectedBranch = "main"
        } else if let first = list.first {
            selectedBranch = first
        }
        isLoading = false
    }
}
