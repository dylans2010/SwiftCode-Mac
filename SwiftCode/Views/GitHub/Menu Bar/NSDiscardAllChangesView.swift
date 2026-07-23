import SwiftUI

public struct NSDiscardAllChangesView: View {
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Discard ALL Changes (⇧⌘U)", systemImage: "trash.slash.fill")
                        .font(.headline)
                        .foregroundStyle(.red)

                    Text("WARNING: This will permanently destroy all unstaged, staged, and untracked changes.")
                        .font(.caption)
                        .foregroundStyle(.red)

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

                    Button("Discard All changes") {
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                try await GitMenuBarCommandExecutor.runGit(args: ["reset", "--hard", "HEAD"])
                                try await GitMenuBarCommandExecutor.runGit(args: ["clean", "-fd"])
                                successMsg = "Local changes discarded. Repository returned to clean state."
                            } catch {
                                errorMsg = "Failed: \(error.localizedDescription)"
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    .disabled(isLoading)
                }
            } else {
                NoActiveProjectView(title: "Discard Changes")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
