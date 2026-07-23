import SwiftUI

public struct NSRebaseView: View {
    @State private var upstreamBranch = "main"
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Rebase (⇧⌘X)", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                        .foregroundStyle(.purple)

                    Text("Rebase current branch onto upstream.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Upstream branch...", text: $upstreamBranch)
                        .textFieldStyle(.roundedBorder)
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

                    Button("Start Rebase") {
                        let upstream = upstreamBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !upstream.isEmpty else { return }
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                try await GitMenuBarCommandExecutor.runGit(args: ["rebase", upstream])
                                successMsg = "Successfully rebased onto '\(upstream)'."
                                upstreamBranch = ""
                            } catch {
                                errorMsg = "Failed: \(error.localizedDescription)"
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(upstreamBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            } else {
                NoActiveProjectView(title: "Rebase")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
