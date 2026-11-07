import AppKit
import SwiftCodeGitHub
import YcodeIDECore
import SwiftUI

@MainActor
public struct PublicRepositoryBrowserView: View {
    public var repoFullName: String
    public var client: GitHubClient
    @Environment(\.dismiss) private var dismiss

    @State private var meta: GitHubRepository?
    @State private var readmeContent = ""
    @State private var selectedBranch = "main"
    @State private var branches: [GitHubBranch] = []
    @State private var activeTab: BrowserTab = .overview
    @State private var errorMessage: String?

    @State private var fileTree: [GitHubTreeEntry] = []
    @State private var selectedFilePath = ""
    @State private var selectedFileContent = ""
    @State private var isLoadingFiles = false
    @State private var isDownloading = false
    @State private var isCloning = false
    @State private var statusMessage: String?

    @State private var isStarred = false

    public enum BrowserTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case files = "Source Tree"
        case commits = "Commits"
        case releases = "Releases"

        public var id: String { rawValue }
    }

    public init(repoFullName: String, client: GitHubClient) {
        self.repoFullName = repoFullName
        self.client = client
    }

    private var ownerAndRepo: (owner: String, repo: String)? {
        let parts = repoFullName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repoFullName)
                        .font(.title3.bold())
                    if let meta {
                        HStack(spacing: 8) {
                            Label("\(meta.stargazersCount)", systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                            Label("\(meta.forksCount)", systemImage: "arrow.triangle.branch")
                                .foregroundStyle(.secondary)
                            Text("Default: \(meta.defaultBranch ?? "main")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }

                Spacer()

                Picker("Section", selection: $activeTab) {
                    ForEach(BrowserTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Spacer()

                HStack(spacing: 10) {
                    Button(isStarred ? "Starred" : "Star") {
                        Task { await toggleStar() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(meta == nil)

                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            switch activeTab {
            case .overview: overviewPane
            case .files: filesPane
            case .commits:
                LiveCommitsHistoryListView(repoFullName: repoFullName, client: client)
                    .padding()
            case .releases:
                LiveReleasesListView(repoFullName: repoFullName, client: client)
                    .padding()
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 900, height: 650)
        .task { await loadRepositoryInfo() }
    }

    private var overviewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let meta {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(meta.description ?? "No description provided.")
                            .font(.body)

                        if let topics = meta.topics, !topics.isEmpty {
                            DiscoverHFlowLayout(spacing: 6) {
                                ForEach(topics, id: \.self) { topic in
                                    Text(topic)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12))
                                        .foregroundStyle(.orange)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("REPOSITORY ACTIONS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            Task { await cloneRepo() }
                        } label: {
                            Label(isCloning ? "Cloning…" : "Clone", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCloning || meta == nil)

                        Button {
                            Task { await forkRepo() }
                        } label: {
                            Label("Fork", systemImage: "arrow.triangle.branch")
                        }
                        .buttonStyle(.bordered)
                        .disabled(meta == nil)

                        Button {
                            Task { await downloadZip() }
                        } label: {
                            Label(isDownloading ? "Downloading…" : "Download ZIP", systemImage: "doc.zipper")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDownloading || meta == nil)

                        Button { copyCloneURL(ssh: false) } label: {
                            Label("Copy HTTPS URL", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .disabled(meta == nil)

                        Button { copyCloneURL(ssh: true) } label: {
                            Label("Copy SSH URL", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .disabled(meta == nil)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("README.md")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    if readmeContent.isEmpty {
                        Text("No README.md resolved or loading…")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Text(readmeContent)
                            .font(.system(.body, design: .serif))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
    }

    private var filesPane: some View {
        HSplitView {
            VStack(spacing: 0) {
                if isLoadingFiles {
                    ProgressView().controlSize(.small).padding()
                    Spacer()
                } else {
                    List(fileTree, id: \.path) { entry in
                        HStack {
                            Image(systemName: entry.type == "tree" ? "folder.fill" : "doc.text")
                                .foregroundStyle(entry.type == "tree" ? .orange : .secondary)
                            Text(entry.path)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if entry.type == "blob" {
                                Task { await loadFileContent(path: entry.path) }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 180, idealWidth: 260, maxWidth: 340)

            VStack(alignment: .leading, spacing: 0) {
                if selectedFilePath.isEmpty {
                    ContentUnavailableView(
                        "No File Selected",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Select a file in the tree to view its contents.")
                    )
                } else {
                    Text(selectedFilePath)
                        .font(.headline)
                        .padding(8)
                    Divider()
                    ScrollView {
                        Text(selectedFileContent)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await loadFileTree() }
    }

    private func loadRepositoryInfo() async {
        guard let ownerAndRepo else {
            errorMessage = "Expected an owner/repo name."
            return
        }
        do {
            let repo = try await client.getRepository(owner: ownerAndRepo.owner, repo: ownerAndRepo.repo)
            meta = repo
            selectedBranch = repo.defaultBranch ?? "main"
            branches = try await client.listBranches(owner: ownerAndRepo.owner, repo: ownerAndRepo.repo, perPage: 100)
            isStarred = try await client.isRepositoryStarred(owner: ownerAndRepo.owner, repo: ownerAndRepo.repo)
            readmeContent = (try? await client.getFileText(owner: ownerAndRepo.owner, repo: ownerAndRepo.repo, path: "README.md", ref: selectedBranch)) ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadFileTree() async {
        guard let ownerAndRepo else { return }
        isLoadingFiles = true
        defer { isLoadingFiles = false }
        do {
            fileTree = try await client.getRepoTree(owner: ownerAndRepo.owner, repo: ownerAndRepo.repo, ref: selectedBranch)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadFileContent(path: String) async {
        guard let ownerAndRepo else { return }
        selectedFilePath = path
        do {
            selectedFileContent = try await client.getFileText(owner: ownerAndRepo.owner, repo: ownerAndRepo.repo, path: path, ref: selectedBranch)
        } catch {
            selectedFileContent = "Could not load \(path): \(error.localizedDescription)"
        }
    }

    private func toggleStar() async {
        guard let ownerAndRepo else { return }
        do {
            try await client.starRepository(owner: ownerAndRepo.owner, repo: ownerAndRepo.repo, starred: !isStarred)
            isStarred.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func forkRepo() async {
        guard let ownerAndRepo else { return }
        do {
            let fork = try await client.forkRepository(owner: ownerAndRepo.owner, repo: ownerAndRepo.repo)
            statusMessage = "Forked to \(fork.fullName)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cloneRepo() async {
        guard let ownerAndRepo, let meta else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Clone Here"
        panel.message = "Choose the folder to clone \(repoFullName) into."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        isCloning = true
        errorMessage = nil
        defer { isCloning = false }
        let cloneURL = meta.cloneUrl ?? "https://github.com/\(repoFullName).git"
        let destination = parent.appendingPathComponent(GitHistory.cloneFolderName(for: cloneURL))
        do {
            try await Task.detached {
                try GitHistory.clone(cloneURL, into: destination)
            }.value
            statusMessage = "Cloned to \(destination.path)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func downloadZip() async {
        guard let ownerAndRepo else { return }
        isDownloading = true
        errorMessage = nil
        defer { isDownloading = false }
        do {
            let data = try await client.downloadRepositoryZip(owner: ownerAndRepo.owner, repo: ownerAndRepo.repo, branch: selectedBranch)
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let destination = downloads.appendingPathComponent("\(ownerAndRepo.repo)-\(selectedBranch).zip")
            try data.write(to: destination)
            statusMessage = "Downloaded ZIP to \(destination.path)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyCloneURL(ssh: Bool) {
        guard let meta else { return }
        let url = ssh
            ? (meta.sshUrl ?? "git@github.com:\(repoFullName).git")
            : (meta.cloneUrl ?? "https://github.com/\(repoFullName).git")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        statusMessage = "Copied \(ssh ? "SSH" : "HTTPS") clone URL."
    }
}

@MainActor
public struct LiveCommitsHistoryListView: View {
    public var repoFullName: String
    public var client: GitHubClient

    @State private var commits: [GitHubCommit] = []
    @State private var isLoading = false

    public init(repoFullName: String, client: GitHubClient) {
        self.repoFullName = repoFullName
        self.client = client
    }

    public var body: some View {
        VStack {
            if isLoading {
                ProgressView().controlSize(.small)
            } else if commits.isEmpty {
                Text("No commits retrieved.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                VStack(spacing: 8) {
                    ForEach(commits, id: \.sha) { commit in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(commit.message.split(separator: "\n").first.map(String.init) ?? commit.message)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text("Authored by \(commit.authorName ?? "Developer")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(commit.sha.prefix(7)))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .task { await loadCommits() }
    }

    private func loadCommits() async {
        let parts = repoFullName.split(separator: "/")
        guard parts.count == 2 else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            commits = try await client.listCommits(owner: String(parts[0]), repo: String(parts[1]), perPage: 30)
        } catch {
            commits = []
        }
    }
}

@MainActor
public struct LiveReleasesListView: View {
    public var repoFullName: String
    public var client: GitHubClient

    @State private var releases: [GitHubRelease] = []
    @State private var isLoading = false

    public init(repoFullName: String, client: GitHubClient) {
        self.repoFullName = repoFullName
        self.client = client
    }

    public var body: some View {
        VStack {
            if isLoading {
                ProgressView().controlSize(.small)
            } else if releases.isEmpty {
                Text("No releases published yet.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                VStack(spacing: 8) {
                    ForEach(releases) { release in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(release.name ?? release.tagName)
                                    .font(.subheadline.bold())
                                if let createdAt = release.createdAt {
                                    Text("Tag: \(release.tagName) • Published on \(createdAt, style: .date)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Tag: \(release.tagName)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .task { await loadReleases() }
    }

    private func loadReleases() async {
        let parts = repoFullName.split(separator: "/")
        guard parts.count == 2 else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            releases = try await client.listReleases(owner: String(parts[0]), repo: String(parts[1]), perPage: 10)
        } catch {
            releases = []
        }
    }
}

public struct DiscoverHFlowLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > width {
                height += lineHeight + spacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += (lineWidth == 0 ? 0 : spacing) + size.width
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: height + lineHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
