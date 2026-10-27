import SwiftUI

@MainActor
struct GitCloneSheetView: View {
    var viewModel: WelcomeViewModel
    @Environment(\.dismiss) var dismiss

    @FocusState private var isURLFocused: Bool
    @State private var remoteURL = ""
    @State private var isCloning = false
    @State private var repositories: [GitHubRepository] = []
    @State private var isLoadingRepos = false
    @State private var errorMessage: String?
    @State private var showingCloneNameAlert = false
    @State private var cloneProjectName = ""
    @State private var pendingCloneParentURL: URL?
    @State private var isHoveringClone = false

    private var isCloneDisabled: Bool {
        remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCloning
    }

    var body: some View {
        VStack(spacing: 18) {
            // Card 1: Remote Repository URL
            remoteURLCard

            // Card 2: GitHub Repositories
            repositoriesCard

            // Action / Error Section
            actionSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    // MARK: - Card 1: Remote Repository URL

    private var remoteURLCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 0.98))

                Text("Remote Repository URL")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }

            Text("Enter the HTTPS clone URL of the Git repository you want to clone.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.6))

            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))

                TextField("https://github.com/username/repository.git", text: $remoteURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .focused($isURLFocused)
                    .autocorrectionDisabled()

                if !remoteURL.isEmpty {
                    Button {
                        remoteURL = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear URL")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isURLFocused
                            ? Color(red: 0.106, green: 0.404, blue: 0.863)
                            : Color.white.opacity(0.12),
                        lineWidth: isURLFocused ? 1.5 : 1
                    )
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Card 2: GitHub Repositories

    private var repositoriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 0.98))

                    Text("Your GitHub Repositories")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                }

                Spacer()

                if !repositories.isEmpty {
                    Button {
                        fetchUserRepositories()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Refresh")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }

            if isLoadingRepos {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching your remote repositories...")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else if repositories.isEmpty {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 44, height: 44)
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }

                    Text("No Connected Repositories")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))

                    Text("Configure your GitHub personal access token in Settings to list and clone your repositories directly.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)

                    Button {
                        SettingsRoutingManager.shared.showSettings()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 10.5))
                            Text("Configure Token in Settings")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(repositories) { repo in
                            let isSelected = (remoteURL == repo.cloneUrl)

                            Button {
                                remoteURL = repo.cloneUrl
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                                        .font(.system(size: 12))
                                        .foregroundStyle(repo.isPrivate ? Color.orange : Color(red: 0.35, green: 0.65, blue: 0.98))
                                        .frame(width: 24, height: 24)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(repo.isPrivate ? Color.orange.opacity(0.12) : Color(red: 0.35, green: 0.65, blue: 0.98).opacity(0.12))
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(repo.name)
                                                .font(.system(size: 12.5, weight: .semibold))
                                                .foregroundStyle(Color.white)

                                            // Visibility badge
                                            Text(repo.isPrivate ? "Private" : "Public")
                                                .font(.system(size: 9.5, weight: .medium))
                                                .foregroundStyle(repo.isPrivate ? Color.orange : Color(red: 0.35, green: 0.65, blue: 0.98))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(
                                                    Capsule()
                                                        .fill(repo.isPrivate ? Color.orange.opacity(0.15) : Color(red: 0.35, green: 0.65, blue: 0.98).opacity(0.15))
                                                )

                                            // Branch badge
                                            HStack(spacing: 2) {
                                                Image(systemName: "arrow.triangle.branch")
                                                    .font(.system(size: 8))
                                                Text("main")
                                                    .font(.system(size: 9.5))
                                            }
                                            .foregroundStyle(Color.white.opacity(0.45))
                                        }

                                        if let desc = repo.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(Color.white.opacity(0.5))
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color(red: 0.106, green: 0.404, blue: 0.863))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            isSelected
                                                ? Color(red: 0.106, green: 0.404, blue: 0.863).opacity(0.18)
                                                : Color.white.opacity(0.02)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(
                                            isSelected
                                                ? Color(red: 0.106, green: 0.404, blue: 0.863).opacity(0.8)
                                                : Color.white.opacity(0.05),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.red)
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.red.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.red.opacity(0.25), lineWidth: 1)
                )
            }

            Button(action: clone) {
                HStack(spacing: 8) {
                    if isCloning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(isCloning ? "Cloning Repository..." : "Clone & Open Project")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: isHoveringClone && !isCloneDisabled
                            ? [Color(red: 0.14, green: 0.46, blue: 0.95), Color(red: 0.08, green: 0.35, blue: 0.80)]
                            : [Color(red: 0.106, green: 0.404, blue: 0.863), Color(red: 0.07, green: 0.30, blue: 0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isCloneDisabled ? Color.clear : Color(red: 0.106, green: 0.404, blue: 0.863).opacity(isHoveringClone ? 0.45 : 0.2),
                    radius: isHoveringClone ? 8 : 4,
                    y: 2
                )
            }
            .buttonStyle(.plain)
            .disabled(isCloneDisabled)
            .opacity(isCloneDisabled ? 0.5 : 1.0)
            .onHover { isHoveringClone = $0 }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Logic

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
