import SwiftUI

public struct NSChooseBranchView: View {
    @State private var branches: [String] = ["main"]
    @State private var selectedBranch = "main"
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let _ = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Choose Branch", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                        .foregroundStyle(.cyan)

                    Picker("Branch", selection: $selectedBranch) {
                        ForEach(branches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .pickerStyle(.menu)
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
                        Button("Switch & Checkout") {
                            Task {
                                isLoading = true
                                successMsg = ""
                                errorMsg = ""
                                do {
                                    try await GitMenuBarCommandExecutor.runGit(args: ["checkout", selectedBranch])
                                    successMsg = "Switched branch to '\(selectedBranch)'."
                                } catch {
                                    errorMsg = "Failed: \(error.localizedDescription)"
                                }
                                isLoading = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isLoading)

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
                NoActiveProjectView(title: "Choose Branch")
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func loadBranches() async {
        isLoading = true
        let list = await GitMenuBarCommandExecutor.getBranchesList()
        branches = list
        if let current = try? await GitMenuBarCommandExecutor.getCurrentBranchName(), list.contains(current) {
            selectedBranch = current
        } else if let first = list.first {
            selectedBranch = first
        }
        isLoading = false
    }
}
