import SwiftUI

@MainActor
struct BranchManagementView: View {
    let owner: String
    let repo: String
    @Binding var currentBranch: String

    @State private var branches: [GitHubBranch] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var newBranchName = ""
    @State private var baseBranch = ""
    @State private var isCreating = false
    @State private var branchToDelete: GitHubBranch?
    @State private var showDeleteConfirm = false
    @State private var notification: BranchNotification?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Branch Directory", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        Task { await loadBranches() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)

                    Button {
                        baseBranch = currentBranch
                        newBranchName = ""
                        showCreateSheet = true
                    } label: {
                        Label("New Branch", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading && branches.isEmpty {
                        GroupBox {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading branches...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    } else if let error = errorMessage, branches.isEmpty {
                        emptyErrorView(error)
                    } else {
                        // Card 1: Active Branch Info
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Active Branch Status", systemImage: "checkmark.circle.fill")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.green)
                                    Spacer()
                                    Text(currentBranch)
                                        .font(.system(.body, design: .monospaced).bold())
                                        .foregroundStyle(.green)
                                }
                                Text("Ensure you are on the correct branch before making edits, committing, or pushing changes. All local work is relative to the active branch.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 2: Branch Directory List
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(branches) { branch in
                                    BranchManagementRow(
                                        branch: branch,
                                        isActive: branch.name == currentBranch,
                                        onSwitch: {
                                            switchTo(branch)
                                        },
                                        onDelete: {
                                            branchToDelete = branch
                                            showDeleteConfirm = true
                                        }
                                    )
                                    if branch.id != branches.last?.id {
                                        Divider().opacity(0.3)
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
            }
        }
        .sourceControlEmbedded()
        .task { await loadBranches() }
        .sheet(isPresented: $showCreateSheet) {
            createBranchSheet
        }
        .confirmationDialog(
            "Delete Branch \(branchToDelete?.name ?? "")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let branch = branchToDelete {
                    Task { await deleteBranch(branch) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this branch? This action cannot be undone.")
        }
        .overlay(alignment: .bottom) {
            if let n = notification {
                notificationBanner(n)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: notification != nil)
    }

    // MARK: - Create Branch Sheet

    private var createBranchSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Create New Branch", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.bottom, 8)

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Branch Name")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("e.g. feature/new-login", text: $newBranchName)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Base Branch")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Picker("Base Branch", selection: $baseBranch) {
                            ForEach(branches) { b in
                                Text(b.name).tag(b.name)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            HStack {
                Button("Cancel") { showCreateSheet = false }
                    .buttonStyle(.bordered)

                Spacer()

                Button("Create Branch") {
                    Task { await createBranch() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Empty / Error View

    private func emptyErrorView(_ error: String) -> some View {
        GroupBox {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.red.opacity(0.8))
                Text("Failed to Load Branches")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await loadBranches() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    // MARK: - Notification Banner

    private func notificationBanner(_ n: BranchNotification) -> some View {
        HStack(spacing: 10) {
            Image(systemName: n.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(n.isError ? .red : .green)
            Text(n.message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                    n.isError ? Color.red.opacity(0.4) : Color.green.opacity(0.4),
                    lineWidth: 1
                ))
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func loadBranches() async {
        guard !owner.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await GitHubService.shared.listBranches(owner: owner, repo: repo)
            branches = fetched
            if !fetched.map(\.name).contains(currentBranch), let first = fetched.first {
                currentBranch = first.name
            }
            if baseBranch.isEmpty { baseBranch = currentBranch }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func switchTo(_ branch: GitHubBranch) {
        currentBranch = branch.name
        showNotification("Switched To Branch \(branch.name)", isError: false)
    }

    private func createBranch() async {
        let name = newBranchName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreating = true
        showCreateSheet = false
        defer { isCreating = false }

        do {
            try await GitHubService.shared.createBranch(
                owner: owner,
                repo: repo,
                branchName: name,
                fromBranch: baseBranch
            )
            await loadBranches()
            currentBranch = name
            showNotification("Branch \(name) Created", isError: false)
        } catch {
            showNotification(error.localizedDescription, isError: true)
        }
    }

    private func deleteBranch(_ branch: GitHubBranch) async {
        do {
            try await GitHubService.shared.deleteBranch(
                owner: owner,
                repo: repo,
                branchName: branch.name
            )
            await loadBranches()
            if currentBranch == branch.name {
                currentBranch = branches.first?.name ?? "main"
            }
            showNotification("Branch \(branch.name) Deleted", isError: false)
        } catch {
            showNotification(error.localizedDescription, isError: true)
        }
    }

    private func showNotification(_ message: String, isError: Bool) {
        notification = BranchNotification(message: message, isError: isError)
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            notification = nil
        }
    }
}

// MARK: - Branch Management Row

private struct BranchManagementRow: View {
    let branch: GitHubBranch
    let isActive: Bool
    let onSwitch: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .foregroundStyle(isActive ? .green : .secondary)
                .font(.callout)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(branch.name)
                        .font(.callout.bold())
                        .foregroundStyle(isActive ? .green : .primary)
                    if branch.protected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }
            }

            Spacer()

            if !isActive {
                Button("Switch") { onSwitch() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if !branch.protected {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct BranchNotification: Equatable {
    let message: String
    let isError: Bool
}
