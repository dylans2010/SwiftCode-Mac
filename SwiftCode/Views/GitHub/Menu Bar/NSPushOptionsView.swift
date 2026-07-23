import SwiftUI

public struct NSPushOptionsView: View {
    @State private var setTrackstream = true
    @State private var pushAllBranches = false
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Push Options", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(.purple)

                    Toggle("Set upstream tracking (--set-upstream)", isOn: $setTrackstream)
                        .toggleStyle(.checkbox)
                        .disabled(isLoading)

                    Toggle("Push all branches (--all)", isOn: $pushAllBranches)
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

                    Button("Apply & Push") {
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                var args = ["push"]
                                if pushAllBranches {
                                    args.append("origin")
                                    args.append("--all")
                                } else {
                                    let branch = try await GitMenuBarCommandExecutor.getCurrentBranchName()
                                    if setTrackstream {
                                        args.append("--set-upstream")
                                    }
                                    args.append("origin")
                                    args.append(branch)
                                }
                                try await GitMenuBarCommandExecutor.runGit(args: args)
                                successMsg = "Pushed with custom configurations applied successfully."
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
                NoActiveProjectView(title: "Push Options")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
