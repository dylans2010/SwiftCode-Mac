import SwiftUI

@MainActor
struct GitCloneSheetView: View {
    var viewModel: WelcomeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var remoteURL = ""
    @State private var isCloning = false
    @State private var repositories: [GitHubRepository] = []
    @State private var isLoadingRepos = false
    @State private var errorMessage: String?
    @State private var showingCloneNameAlert = false
    @State private var cloneProjectName = ""
    @State private var pendingCloneParentURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Clone Repository", systemImage: "arrow.triangle.pull")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 0.98))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 16) {
                    // Card 1: Remote URL
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Remote Repository URL")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white)

                        Text("Enter the HTTPS URL of the Git repository to clone.")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.6))

                        TextField("https://github.com/username/repository.git", text: $remoteURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                    // Card 2: Your GitHub Repositories
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Your GitHub Repositories", systemImage: "list.bullet")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 0.98))
                            Spacer()
                        }

                        if isLoadingRepos {
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Fetching your remote repositories...")
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity, minHeight: 100)
                        } else if repositories.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "folder.badge.questionmark")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Color.white.opacity(0.35))
                                Text("No Remote Repositories Found")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.7))
                                Text("Configure your GitHub personal access token in Settings to list repos.")
                                    .font(.caption2)
                                    .foregroundStyle(Color.white.opacity(0.45))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 90)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(repositories) { repo in
                                    Button {
                                        remoteURL = repo.cloneUrl
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                                                .foregroundStyle(repo.isPrivate ? Color.orange : Color(red: 0.35, green: 0.65, blue: 0.98))
                                                .frame(width: 18)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(repo.name)
                                                    .font(.system(size: 12.5, weight: .semibold))
                                                    .foregroundStyle(Color.white)
                                                if let desc = repo.description, !desc.isEmpty {
                                                    Text(desc)
                                                        .font(.caption2)
                                                        .foregroundStyle(Color.white.opacity(0.55))
                                                        .lineLimit(1)
                                                }
                                            }

                                            Spacer()

                                            if remoteURL == repo.cloneUrl {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color(red: 0.106, green: 0.404, blue: 0.863))
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(remoteURL == repo.cloneUrl ? Color(red: 0.106, green: 0.404, blue: 0.863).opacity(0.2) : Color.white.opacity(0.03))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(remoteURL == repo.cloneUrl ? Color(red: 0.106, green: 0.404, blue: 0.863) : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                    // Actions Card
                    VStack(alignment: .leading, spacing: 12) {
                        if let error = errorMessage {
                            Text(error)
                                .foregroundStyle(Color.red)
                                .font(.caption)
                        }

                        Button(action: clone) {
                            HStack {
                                if isCloning {
                                    ProgressView().scaleEffect(0.8).padding(.trailing, 8)
                                } else {
                                    Image(systemName: "arrow.triangle.pull")
                                }
                                Text(isCloning ? "Cloning..." : "Clone & Open Project")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .tint(Color(red: 0.106, green: 0.404, blue: 0.863))
                        .disabled(remoteURL.isEmpty || isCloning)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
            }
        }
        .sourceControlEmbedded()
        .frame(width: 520, height: 500)
        .background(Color(red: 0.082, green: 0.102, blue: 0.180))
        .preferredColorScheme(.dark)
        .onAppear {
            fetchUserRepositories()
        }
        .alert("Project Name", isPresented: $showingCloneNameAlert) {
            TextField("Enter project name", text: $cloneProjectName)
            Button("Clone") {
                if let parentURL = pendingCloneParentURL {
                    executeClone(to: parentURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enter a name for the cloned project folder.")
        }
    }

    private func executeClone(to parentURL: URL) {
        let destination = parentURL.appendingPathComponent(cloneProjectName)
        isCloning = true
        errorMessage = nil
        Task {
            do {
                guard let remote = URL(string: remoteURL) else {
                    throw AppError.validationError("Invalid Remote URL")
                }
                let token = try? await KeychainService.shared.get(account: "github-pat")
                try await GitService.shared.clone(remoteURL: remote, destinationURL: destination, token: token)
                let project = try await ProjectSessionStore.shared.importProject(from: destination, name: cloneProjectName)
                await ProjectSessionStore.shared.openProject(project)
                dismiss()
            } catch {
                errorMessage = "Clone failed: \(error.localizedDescription)"
                LoggingTool.error("Clone failed: \(error)")
            }
            isCloning = false
        }
    }

    private func fetchUserRepositories() {
        Task {
            guard let token = try? await KeychainService.shared.get(account: "github-pat") else { return }
            isLoadingRepos = true
            do {
                repositories = try await GitHubService.shared.fetchRepositories(token: token)
            } catch {
                errorMessage = "Failed to fetch repositories: \(error.localizedDescription)"
                LoggingTool.error("Repo fetch failed: \(error)")
            }
            isLoadingRepos = false
        }
    }

    private func clone() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Select clone destination"

        if panel.runModal() == .OK, let url = panel.url {
            pendingCloneParentURL = url
            if let remote = URL(string: remoteURL) {
                cloneProjectName = remote.deletingPathExtension().lastPathComponent
            } else {
                cloneProjectName = "ClonedProject"
            }
            showingCloneNameAlert = true
        }
    }
}
