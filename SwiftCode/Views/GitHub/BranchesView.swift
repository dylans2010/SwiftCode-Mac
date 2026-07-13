import SwiftUI

@MainActor
struct BranchesView: View {
    var gitViewModel: GitViewModel
    let project: Project?
    @Binding var showSuccess: Bool
    @Binding var successMessage: String?
    @Binding var showError: Bool
    @Binding var errorMessage: String?

    @State private var newBranchName = ""
    @State private var showCreateBranchSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header actions row
            HStack(spacing: 12) {
                Label("Branch Management", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                Button {
                    gitViewModel.refreshBranches()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    showCreateBranchSheet = true
                } label: {
                    Label("New Branch", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if gitViewModel.branches.isEmpty {
                GitHubEmptyStateView(
                    title: "No Branches Resolved",
                    description: "Your repository has no tracked branches or has not been initialized with Git yet.",
                    systemImage: "arrow.triangle.branch",
                    accentColor: .orange,
                    actionTitle: "Create New Branch"
                ) {
                    showCreateBranchSheet = true
                }
            } else {
                List(gitViewModel.branches) { branch in
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(branch.isCurrent ? .orange : .secondary)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(branch.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)

                                if branch.isCurrent {
                                    Text("CURRENT")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12))
                                        .foregroundStyle(.orange)
                                        .cornerRadius(4)
                                }
                            }

                            Text(branch.trackingRemote ?? "Local branch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            if !branch.isCurrent {
                                Button("Checkout") {
                                    gitViewModel.checkout(branch)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Delete") {
                                    gitViewModel.deleteBranch(branch)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .sheet(isPresented: $showCreateBranchSheet) {
            createBranchSheet
        }
    }

    private var createBranchSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Create New Branch", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Cancel") {
                    showCreateBranchSheet = false
                }
                .buttonStyle(.bordered)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Branch Name", text: $newBranchName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            Button {
                gitViewModel.createBranch(named: newBranchName)
                newBranchName = ""
                showCreateBranchSheet = false
            } label: {
                Text("Create Branch")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
        .frame(width: 400)
    }
}
