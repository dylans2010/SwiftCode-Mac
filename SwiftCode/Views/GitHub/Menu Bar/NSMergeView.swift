import SwiftUI

public struct NSMergeView: View {
    @State private var branches: [String] = []
    @State private var branchToMerge = ""
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Merge (⇧⌘M)", systemImage: "arrow.triangle.merge")
                        .font(.headline)
                        .foregroundStyle(.blue)

                    Text("Merge another branch into active HEAD.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !branches.isEmpty {
                        Picker("Select Branch", selection: $branchToMerge) {
                            ForEach(branches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isLoading)
                    } else {
                        TextField("Branch name to merge...", text: $branchToMerge)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isLoading)
                    }

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
                        Button("Merge Branch") {
                            let name = branchToMerge.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            Task {
                                isLoading = true
                                successMsg = ""
                                errorMsg = ""
                                do {
                                    try await GitMenuBarCommandExecutor.runGit(args: ["merge", name])
                                    successMsg = "Successfully merged branch '\(name)'."
                                    branchToMerge = ""
                                } catch {
                                    errorMsg = "Failed: \(error.localizedDescription)"
                                }
                                isLoading = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(branchToMerge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)

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
                NoActiveProjectView(title: "Merge")
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
            branchToMerge = first
        } else {
            branchToMerge = ""
        }
        isLoading = false
    }
}
