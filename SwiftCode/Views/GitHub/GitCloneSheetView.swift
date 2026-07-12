import SwiftUI

struct GitCloneSheetView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var remoteURL = ""
    @State private var isCloning = false
    @State private var repositories: [GitHubRepository] = []
    @State private var isLoadingRepos = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Card 1: Remote Repository URL
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Remote Repository Origin", systemImage: "globe")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        Text("Enter the HTTPS URL of the Git repository you wish to clone locally.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Remote URL (HTTPS)", text: $remoteURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Card 2: Your GitHub Repositories
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Your GitHub Repositories", systemImage: "list.bullet")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        if isLoadingRepos {
                            VStack {
                                ProgressView()
                                Text("Fetching your remote repositories...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                        } else if repositories.isEmpty {
                            ContentUnavailableView(
                                "No Remote Repositories Found",
                                systemImage: "folder.badge.questionmark",
                                description: Text("Make sure your personal access token is configured with repo permissions.")
                            )
                            .frame(height: 150)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(repositories) { repo in
                                    Button {
                                        remoteURL = repo.cloneUrl
                                    } label: {
                                        HStack {
                                            Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                                                .foregroundStyle(repo.isPrivate ? .orange : .blue)
                                                .frame(width: 20)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(repo.name)
                                                    .font(.body.bold())
                                                    .foregroundStyle(.primary)
                                                if let desc = repo.description, !desc.isEmpty {
                                                    Text(desc)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer()

                                            if remoteURL == repo.cloneUrl {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        .padding(8)
                                        .background(remoteURL == repo.cloneUrl ? Color.green.opacity(0.05) : Color.secondary.opacity(0.04))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Actions Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        if let error = errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
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
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.orange)
                        .disabled(remoteURL.isEmpty || isCloning)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: 550, height: 600)
        .onAppear {
            fetchUserRepositories()
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
            isCloning = true
            Task {
                do {
                    guard let remote = URL(string: remoteURL) else {
                        throw AppError.validationError("Invalid Remote URL")
                    }
                    let folderName = remote.deletingPathExtension().lastPathComponent
                    let destination = url.appendingPathComponent(folderName)

                    let token = try? await KeychainService.shared.get(account: "github-pat")
                    try await GitService.shared.clone(remoteURL: remote, destinationURL: destination, token: token)
                    let project = try await ProjectSessionStore.shared.importProject(from: destination)
                    await ProjectSessionStore.shared.openProject(project)
                    dismiss()
                } catch {
                    errorMessage = "Clone failed: \(error.localizedDescription)"
                    LoggingTool.error("Clone failed: \(error)")
                }
                isCloning = false
            }
        }
    }
}
