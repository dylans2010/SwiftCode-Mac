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
        VStack(spacing: 0) {
            HStack {
                Text("Clone Repository")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            VStack(spacing: 20) {
                TextField("Remote URL (HTTPS)", text: $remoteURL)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                if isLoadingRepos {
                    ProgressView("Fetching your repositories...")
                        .padding()
                } else if !repositories.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Your GitHub Repositories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        List(repositories) { repo in
                            HStack {
                                Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                                    .foregroundStyle(repo.isPrivate ? .orange : .blue)
                                    .frame(width: 20)

                                VStack(alignment: .leading) {
                                    Text(repo.name)
                                        .font(.body)
                                    if let desc = repo.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                remoteURL = repo.cloneUrl
                            }
                            .padding(.vertical, 4)
                        }
                        .listStyle(.inset)
                        .frame(height: 200)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                        .padding(.horizontal)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                if isCloning {
                    ProgressView("Cloning...")
                }

                Button(action: clone) {
                    Text(isCloning ? "Cloning..." : "Clone & Open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(remoteURL.isEmpty || isCloning)
                .padding()
            }
            .padding(.vertical)
        }
        .frame(width: 500)
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
