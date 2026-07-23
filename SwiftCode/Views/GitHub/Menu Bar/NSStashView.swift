import SwiftUI

public struct NSStashView: View {
    @State private var stashMessage = ""
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Stash", systemImage: "archivebox.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text("Stash away local modifications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Optional stash message...", text: $stashMessage)
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
                NoActiveProjectView(title: "Stash")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
