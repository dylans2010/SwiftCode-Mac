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

    var body: some View {
        @Bindable var contextBindable = context

        List {
            // Display Preference Control Section
            Section(header: Text("GitHub Data Display Mode").font(.system(size: 10, weight: .bold)).foregroundStyle(.blue)) {
                VStack(alignment: .leading, spacing: 10) {
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
                .padding(.vertical, 4)
            }

            // Local Details Info Section
            Section(header: Text("Local Workspace Status").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)) {
                VStack(alignment: .leading, spacing: 8) {
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
                .padding(.vertical, 4)
            }

            if let details = context.cachedMetadata {
                // Connected Remote Details Section
                Section(header: Text("Connected Repository Details").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(details.fullName)
                                .font(.headline)
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

                        Divider()

                        // Clone URLs
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Clone URLs")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)

                            HStack {
                                Text("HTTPS")
                                    .font(.caption2.bold())
                                    .frame(width: 50, alignment: .leading)
                                Text(details.cloneUrl)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                            }

                            if let ssh = details.sshUrl {
                                HStack {
                                    Text("SSH")
                                        .font(.caption2.bold())
                                        .frame(width: 50, alignment: .leading)
                                    Text(ssh)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(6)
                                        .background(Color.secondary.opacity(0.12))
                                        .cornerRadius(4)
                                }
                            }
                        }

                        Divider()

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                            GridRow {
                                Text("Visibility:")
                                    .fontWeight(.bold)
                                Text(details.isPrivate ? "Private" : "Public")
                                    .foregroundColor(details.isPrivate ? .red : .green)

                                Text("Default Branch:")
                                    .fontWeight(.bold)
                                Text(details.defaultBranch ?? "main")
                            }

                            GridRow {
                                Text("Primary Language:")
                                    .fontWeight(.bold)
                                Text(details.language ?? "Swift")

                                if let size = details.size {
                                    Text("Repository Size:")
                                        .fontWeight(.bold)
                                    Text(String(format: "%.2f MB", Double(size) / 1024.0))
                                }
                            }

                            GridRow {
                                Text("Open Issues:")
                                    .fontWeight(.bold)
                                Text("\(details.openIssuesCount)")

                                Text("GitHub Releases:")
                                    .fontWeight(.bold)
                                Text("\(context.loadedReleasesCount > 0 ? "\(context.loadedReleasesCount)" : "N/A")")
                            }

                            GridRow {
                                Text("Remote Branches:")
                                    .fontWeight(.bold)
                                Text("\(context.loadedBranchesCount > 0 ? "\(context.loadedBranchesCount)" : "N/A")")

                                Text("Open Pull Requests:")
                                    .fontWeight(.bold)
                                Text("\(context.loadedPullRequestsCount > 0 ? "\(context.loadedPullRequestsCount)" : "N/A")")
                            }
                        }
                        .font(.subheadline)

                        // Languages list
                        if !context.loadedLanguages.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Repository Languages")
                                    .font(.subheadline.bold())
                                HFlowLayout(context.loadedLanguages, spacing: 6) { language in
                                    Text(language)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.12))
                                        .foregroundColor(.green)
                                        .cornerRadius(6)
                                }
                            }
                        }

                        // Topics list
                        if let topics = details.topics, !topics.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Topics")
                                    .font(.subheadline.bold())
                                HFlowLayout(topics, spacing: 6) { topic in
                                    Text(topic)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .cornerRadius(6)
                                }
                            }
                        }

                        Divider()

                        // Key Statistics
                        HStack(spacing: 20) {
                            statIndicator(title: "Stars", value: "\(details.stargazersCount)", icon: "star.fill", color: .yellow)
                            statIndicator(title: "Forks", value: "\(details.forksCount)", icon: "arrow.branch", color: .orange)
                            statIndicator(title: "Subscribers", value: "\(details.subscribersCount ?? 0)", icon: "eye.fill", color: .purple)
                            statIndicator(title: "Network", value: "\(details.networkCount ?? 0)", icon: "network", color: .blue)
                        }

                        Divider()

                        Button("Disconnect Repository") {
                            context.disconnectRepository()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.vertical, 4)
                }
            } else if let repo = context.connectedRepository {
                // Connection without metadata loaded Section
                Section(header: Text("Linked Remote Details").font(.system(size: 10, weight: .bold)).foregroundStyle(.blue)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Linked Remote: \(repo)")
                            .font(.headline)

                        Text("Details for this repository have not been loaded or the API is unavailable.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Load Repository Metadata") {
                                Task {
                                    isLoading = true
                                    await context.fetchMetadata()
                                    await gitViewModel.refreshStatus()
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
                    .padding(.vertical, 4)
                }
            } else {
                // Connect Repository Section
                Section(header: Text("Connect Repository").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)) {
                    VStack(alignment: .leading, spacing: 14) {
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
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.sidebar)
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

    private func statIndicator(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
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

// Simple Helper for Horizontal Flow Layout of Topics
struct HFlowLayout: View {
    let spacing: CGFloat
    let items: [AnyView]

    init<Data: RandomAccessCollection, Content: View>(
        _ data: Data,
        spacing: CGFloat = 8,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.spacing = spacing
        self.items = data.map { AnyView(content($0)) }
    }

    var body: some View {
        // Safe cross-platform fallback for dynamic grid topics display
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: spacing) {
            ForEach(0..<items.count, id: \.self) { index in
                items[index]
            }
        }
    }
}
