import SwiftUI

@MainActor
struct RepositoryDetailView: View {
    let project: Project?
    var gitViewModel: GitViewModel
    var onDismiss: () -> Void

    @State private var repoToConnect = ""
    @State private var cloneURLStr = ""
    @State private var isLoading = false

    @State private var showSuccess = false
    @State private var successMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""

    private var context: RepositoryContext {
        RepositoryContext.shared
    }

    private var ownerAndRepo: (String, String)? {
        guard let repoStr = context.connectedRepository, !repoStr.isEmpty else { return nil }
        let parts = repoStr.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    var body: some View {
        @Bindable var contextBindable = context

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Display Preference Control
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("GitHub Data Display Mode", systemImage: "eye.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        Text("Choose the scope of GitHub information shown throughout the workspace:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Display Mode", selection: $contextBindable.displayMode) {
                            ForEach(RepositoryContext.DisplayMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Local Details Info Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Local Workspace Status", systemImage: "laptopcomputer")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("Project Path:")
                                    .fontWeight(.bold)
                                Text(project?.directoryURL.path ?? "N/A")
                                    .font(.system(.body, design: .monospaced))
                            }
                            GridRow {
                                Text("Git Status:")
                                    .fontWeight(.bold)
                                if let status = gitViewModel.status {
                                    Text("Initialized (Branch: \(status.branchName))")
                                } else {
                                    Text("Not Initialized")
                                        .foregroundStyle(.red)
                                }
                            }
                            if let status = gitViewModel.status {
                                GridRow {
                                    Text("Uncommitted:")
                                        .fontWeight(.bold)
                                    Text("\(status.files.count) files modified")
                                }
                                GridRow {
                                    Text("Sync Info:")
                                        .fontWeight(.bold)
                                    Text("\(status.ahead) Ahead / \(status.behind) Behind")
                                }
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                if let details = context.cachedMetadata {
                    // Connected Remote Details Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Connected Repository Details", systemImage: "link")
                                    .font(.headline)
                                    .foregroundStyle(.green)

                                Spacer()

                                Button {
                                    Task {
                                        await context.fetchMetadata()
                                    }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .disabled(isLoading)
                            }

                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                                GridRow {
                                    Text("Name:")
                                        .fontWeight(.bold)
                                    Text(details.fullName)
                                }
                                GridRow {
                                    Text("Remote URL:")
                                        .fontWeight(.bold)
                                    Text(details.cloneUrl)
                                        .font(.system(.body, design: .monospaced))
                                }
                                GridRow {
                                    Text("Default Branch:")
                                        .fontWeight(.bold)
                                    Text(details.defaultBranch)
                                }
                                GridRow {
                                    Text("Hosting Provider:")
                                        .fontWeight(.bold)
                                    Text("GitHub")
                                }
                                GridRow {
                                    Text("Statistics:")
                                        .fontWeight(.bold)
                                    Text("\(details.stargazersCount) Stars • \(details.forksCount) Forks • \(details.openIssuesCount) Open Issues")
                                }
                            }
                            .font(.subheadline)

                            Divider()
                                .padding(.vertical, 8)

                            Button("Disconnect Repository") {
                                context.disconnectRepository()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                } else if let repo = context.connectedRepository {
                    // Has connection but metadata not yet loaded
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Linked Remote: \(repo)")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            Text("Details for this repository have not been loaded or the API is unavailable.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Load Repository Metadata") {
                                    Task {
                                        isLoading = true
                                        await context.fetchMetadata()
                                        isLoading = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Disconnect Repository") {
                                    context.disconnectRepository()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                } else {
                    // No repository connected: offer connection tools
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Connect Repository", systemImage: "link.badge.plus")
                                .font(.headline)
                                .foregroundStyle(.orange)

                            Text("Connect an existing GitHub repository by name:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack {
                                TextField("owner/repo (e.g. apple/swift)", text: $repoToConnect)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()

                                Button("Connect") {
                                    connectRepository(repoToConnect)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .disabled(repoToConnect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            Divider()
                                .padding(.vertical, 8)

                            Text("Or, clone a remote repository into this project workspace:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack {
                                TextField("https://github.com/owner/repo.git", text: $cloneURLStr)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()

                                Button("Clone") {
                                    cloneAndConnect(cloneURLStr)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .disabled(cloneURLStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding()
        }
        .onAppear {
            if context.cachedMetadata == nil {
                Task {
                    await context.fetchMetadata()
                }
            }
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") {}
        } message: {
            Text(successMessage)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Actions Helper

    private func connectRepository(_ repoName: String) {
        guard let project = project else { return }

        isLoading = true
        Task {
            do {
                let dirURL = project.directoryURL
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)

                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["init"],
                    workingDirectory: dirURL
                )

                let authenticatedURL = "https://github.com/\(repoName).git"

                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["remote", "remove", "origin"],
                    workingDirectory: dirURL
                )

                _ = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["remote", "add", "origin", authenticatedURL],
                    workingDirectory: dirURL
                )

                context.connectRepository(repoName)

                await gitViewModel.refreshStatus()
                successMessage = "Successfully connected to \(repoName) and configured remote origin."
                showSuccess = true
            } catch {
                errorMessage = "Failed to connect repository: \(error.localizedDescription)"
                showError = true
            }
            isLoading = false
        }
    }

    private func cloneAndConnect(_ cloneURLStr: String) {
        guard let project = project else { return }
        guard let cloneURL = URL(string: cloneURLStr) else {
            errorMessage = "Invalid clone URL format."
            showError = true
            return
        }

        isLoading = true
        Task {
            do {
                let dirURL = project.directoryURL
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)

                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["clone", cloneURL.absoluteString, "."],
                    workingDirectory: dirURL
                )

                if result.exitCode == 0 {
                    var repoName = ""
                    let pathComponents = cloneURL.pathComponents
                    if pathComponents.count >= 2 {
                        let owner = pathComponents[pathComponents.count - 2]
                        var repo = pathComponents[pathComponents.count - 1]
                        if repo.hasSuffix(".git") {
                            repo = String(repo.dropLast(4))
                        }
                        repoName = "\(owner)/\(repo)"
                    }

                    if !repoName.isEmpty {
                        context.connectRepository(repoName)
                    }

                    await gitViewModel.refreshStatus()
                    successMessage = "Successfully cloned repository and connected project."
                    showSuccess = true
                } else {
                    errorMessage = "Failed to clone repository: \(result.stderr)"
                    showError = true
                }
            } catch {
                errorMessage = "Failed to run clone command: \(error.localizedDescription)"
                showError = true
            }
            isLoading = false
        }
    }
}
