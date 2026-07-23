import SwiftUI

public struct NSCherryPickView: View {
    @State private var commitSHA = ""
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Cherry Pick", systemImage: "arrow.triangle.pull")
                        .font(.headline)
                        .foregroundStyle(.purple)

                    Text("Apply change introduced by existing commit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Commit SHA (e.g. d6f3e12)...", text: $commitSHA)
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

                    Button("Apply Commit") {
                        let sha = commitSHA.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !sha.isEmpty else { return }
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                try await GitMenuBarCommandExecutor.runGit(args: ["cherry-pick", sha])
                                successMsg = "Successfully cherry-picked commit: \(sha)"
                                commitSHA = ""
                            } catch {
                                errorMsg = "Failed: \(error.localizedDescription)"
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(commitSHA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            } else {
                NoActiveProjectView(title: "Cherry Pick")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
