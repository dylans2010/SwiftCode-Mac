import SwiftUI

public struct NSPushView: View {
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Push (⇧⌘H)", systemImage: "arrow.up.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.blue)

                    Text("Push local commits to your remote origin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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

                    Button("Push commits") {
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                let branch = try await GitMenuBarCommandExecutor.getCurrentBranchName()
                                try await GitMenuBarCommandExecutor.runGit(args: ["push", "origin", branch])
                                successMsg = "Successfully pushed commits to remote '\(branch)'."
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
            } else {
                NoActiveProjectView(title: "Push")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
