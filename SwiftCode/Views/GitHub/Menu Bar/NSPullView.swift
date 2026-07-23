import SwiftUI

public struct NSPullView: View {
    @State private var useRebase = false
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Pull", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.cyan)

                    Text("Fetch and integrate remote changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Pull changes") {
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                var args = ["pull", "origin"]
                                if useRebase {
                                    args.append("--rebase")
                                }
                                try await GitMenuBarCommandExecutor.runGit(args: args)
                                successMsg = "Pulled remote changes successfully."
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
                NoActiveProjectView(title: "Pull")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
