import SwiftUI

// MARK: - Branch Management View

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
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()

                if isLoading && branches.isEmpty {
                    ProgressView("Loading Branches…")
                        .tint(.green)
                } else if branches.isEmpty, let error = errorMessage {
                    emptyErrorView(error)
                } else {
                    branchList
                }
            }
            .navigationTitle("Branches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            Task { await loadBranches() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.green)
                        }
                        .disabled(isLoading)

                        Button {
                            baseBranch = currentBranch
                            newBranchName = ""
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
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
                Text("Are you sure you want to delete ths Branch? This action cannot be undone.")
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
        .preferredColorScheme(.dark)
        .task { await loadBranches() }
    }

    // MARK: - Branch List

    private var branchList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Active branch indicator
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Active Branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(currentBranch)
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.15), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.05))

                Divider().opacity(0.2)

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
                    Divider().opacity(0.1).padding(.leading, 50)
                }
            }
        }
    }

    // MARK: - Create Branch Sheet

    private var createBranchSheet: some View {
        NavigationStack {
            Form {
                Section("New Branch") {
                    TextField("new-name", text: $newBranchName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Base Branch") {
                    Picker("Base", selection: $baseBranch) {
                        ForEach(branches) { b in
                            Text(b.name).tag(b.name)
                        }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .navigationTitle("Create Branch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createBranch() }
                    }
                    .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                    .overlay {
                        if isCreating { ProgressView().scaleEffect(0.8) }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty / Error View

    private func emptyErrorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.red.opacity(0.7))
            Text("Failed To Load Branches")
                .font(.headline)
                .foregroundStyle(.white)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                Task { await loadBranches() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    // MARK: - Notification Banner

    private func notificationBanner(_ n: BranchNotification) -> some View {
        HStack(spacing: 10) {
            Image(systemName: n.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(n.isError ? .red : .green)
            Text(n.message)
                .font(.subheadline)
                .foregroundStyle(.white)
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
            // PLACEHOLDER: DELETE /repos/{owner}/{repo}/git/refs/heads/{branch.name}
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
                        .font(.callout)
                        .foregroundStyle(isActive ? .white : .primary)
                    if branch.protected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.15), in: Capsule())
                    }
                }
            }

            Spacer()

            if !isActive {
                Button("Switch") { onSwitch() }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
                    .buttonStyle(.plain)

                if !branch.protected {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isActive ? Color.green.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Supporting Types

private struct BranchNotification: Equatable {
    let message: String
    let isError: Bool
}
