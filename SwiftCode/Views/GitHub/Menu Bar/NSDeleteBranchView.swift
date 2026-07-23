import SwiftUI

public struct NSDeleteBranchView: View {
    @State private var branches: [String] = []
    @State private var branchToDelete = ""
    @State private var forceDelete = false
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Delete Branch (⇧⌘D)", systemImage: "trash.fill")
                        .font(.headline)
                        .foregroundStyle(.red)

                    if !branches.isEmpty {
                        Picker("Select Branch", selection: $branchToDelete) {
                            ForEach(branches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isLoading)
                    } else {
                        TextField("Branch name...", text: $branchToDelete)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isLoading)
                    }

                    Toggle("Force delete branch (-D)", isOn: $forceDelete)
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

                    HStack {
                        Button("Delete Branch") {
                            let name = branchToDelete.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            Task {
                                isLoading = true
                                successMsg = ""
                                errorMsg = ""
                                do {
                                    let argFlag = forceDelete ? "-D" : "-d"
                                    try await GitMenuBarCommandExecutor.runGit(args: ["branch", argFlag, name])
                                    successMsg = "Branch '\(name)' deleted successfully."
                                    branchToDelete = ""
                                    await loadBranches()
                                } catch {
                                    errorMsg = "Failed: \(error.localizedDescription)"
                                }
                                isLoading = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(branchToDelete.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)

                        Button("Refresh") {
                            Task {
                                await loadBranches()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isLoading)
                    }
                }
                .onAppear {
                    Task {
                        await loadBranches()
                    }
                }
            } else {
                NoActiveProjectView(title: "Delete Branch")
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func loadBranches() async {
        isLoading = true
        let list = await GitMenuBarCommandExecutor.getBranchesList()
        if let current = try? await GitMenuBarCommandExecutor.getCurrentBranchName() {
            branches = list.filter { $0 != current }
        } else {
            branches = list
        }
        if let first = branches.first {
            branchToDelete = first
        } else {
            branchToDelete = ""
        }
        isLoading = false
    }
}
