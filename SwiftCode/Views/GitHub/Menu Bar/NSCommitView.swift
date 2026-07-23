import SwiftUI

public struct NSCommitView: View {
    @State private var commitMessage = ""
    @State private var amend = false
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Commit (⇧⌘C)", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)

                    Text("Stage and commit your active changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Commit message...", text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLoading)

                    Toggle("Amend last commit", isOn: $amend)
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
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Commit Changes") {
                        let msg = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !msg.isEmpty else { return }
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                try await GitMenuBarCommandExecutor.runGit(args: ["add", "-A"])
                                var args = ["commit", "-m", msg]
                                if amend {
                                    args.append("--amend")
                                }
                                try await GitMenuBarCommandExecutor.runGit(args: args)
                                successMsg = "Successfully committed changes: '\(msg)'"
                                commitMessage = ""
                                amend = false
                            } catch {
                                errorMsg = "Failed: \(error.localizedDescription)"
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            } else {
                NoActiveProjectView(title: "Commit")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
