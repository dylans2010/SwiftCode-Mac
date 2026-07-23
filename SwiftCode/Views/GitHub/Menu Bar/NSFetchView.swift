import SwiftUI

public struct NSFetchView: View {
    @State private var prune = true
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Fetch (⇧⌘E)", systemImage: "arrow.down.and.line.horizontal.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.blue)

                    Text("Download references from remote without merging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Prune stale remote branches (--prune)", isOn: $prune)
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

                    Button("Fetch References") {
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                var args = ["fetch", "origin"]
                                if prune {
                                    args.append("--prune")
                                }
                                try await GitMenuBarCommandExecutor.runGit(args: args)
                                successMsg = "References fetched successfully."
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
                NoActiveProjectView(title: "Fetch")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
