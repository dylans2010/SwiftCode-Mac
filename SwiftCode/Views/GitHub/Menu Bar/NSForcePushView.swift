import SwiftUI

public struct NSForcePushView: View {
    @State private var useForceWithLease = true
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Force Push", systemImage: "exclamationmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.red)

                    Text("WARNING: Force pushing overwrites history on the remote origin.")
                        .font(.caption2)
                        .foregroundStyle(.red)

                    Toggle("Use force with lease (Safer)", isOn: $useForceWithLease)
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

                    Button("Force Push") {
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                let branch = try await GitMenuBarCommandExecutor.getCurrentBranchName()
                                let forceFlag = useForceWithLease ? "--force-with-lease" : "--force"
                                try await GitMenuBarCommandExecutor.runGit(args: ["push", "origin", branch, forceFlag])
                                successMsg = "Force push to '\(branch)' triggered successfully."
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
                NoActiveProjectView(title: "Force Push")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
