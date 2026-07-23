import SwiftUI

public struct NSCreateBranchView: View {
    @State private var branchName = ""
    @State private var checkout = true
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Create Branch", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.cyan)

                    TextField("Branch name...", text: $branchName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLoading)

                    Toggle("Checkout branch immediately", isOn: $checkout)
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

                    Button("Create Branch") {
                        let name = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                if checkout {
                                    try await GitMenuBarCommandExecutor.runGit(args: ["checkout", "-b", name])
                                } else {
                                    try await GitMenuBarCommandExecutor.runGit(args: ["branch", name])
                                }
                                successMsg = "Branch '\(name)' created successfully."
                                branchName = ""
                            } catch {
                                errorMsg = "Failed: \(error.localizedDescription)"
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            } else {
                NoActiveProjectView(title: "Create Branch")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
