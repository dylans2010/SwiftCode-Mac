import SwiftUI

@MainActor
struct ReleasesView: View {
    let project: Project?
    @Binding var showSuccess: Bool
    @Binding var successMessage: String?
    @Binding var showError: Bool
    @Binding var errorMessage: String?

    @State private var releases: [GitHubReleaseInfo] = []
    @State private var isFetching = false
    @State private var selectedRelease: GitHubReleaseInfo?

    // Draft release state
    @State private var showDraftSheet = false
    @State private var draftTag = ""
    @State private var draftTitle = ""
    @State private var draftNotes = ""
    @State private var isPublishingDraft = false

    // AI generation state
    @State private var isGeneratingAINotes = false

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
        VStack(spacing: 0) {
            if context.displayMode == .connectedRepository && context.connectedRepository == nil {
                disconnectedPlaceholder
            } else {
                mainContent
            }
        }
        .onAppear {
            fetchReleases()
        }
        .onChange(of: context.displayMode) {
            fetchReleases()
        }
        .onChange(of: context.syncEventsCount) {
            fetchReleases()
        }
        .sheet(isPresented: $showDraftSheet) {
            draftReleaseSheetView
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header actions row
            HStack(spacing: 12) {
                Label("Repository Releases", systemImage: "shippingbox.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Spacer()

                Button {
                    fetchReleases()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isFetching)

                Button {
                    showDraftSheet = true
                } label: {
                    Label("Draft New Release", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(context.connectedRepository == nil)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetching {
                GitHubLoadingView(message: "Loading releases...")
            } else if releases.isEmpty {
                GitHubEmptyStateView(
                    title: "No Releases Published",
                    description: "No GitHub releases found for this repository. Draft one now!",
                    systemImage: "shippingbox",
                    accentColor: .green,
                    actionTitle: "Draft Release"
                ) {
                    showDraftSheet = true
                }
            } else {
                List {
                    Section("Release Catalog Directory") {
                        ForEach(releases) { release in
                            Button {
                                selectedRelease = release
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(.green)
                                        .font(.title2)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(release.name ?? release.tagName)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)

                                        HStack(spacing: 8) {
                                            Text(release.tagName)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                            Text("•")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text("Published on \(release.createdAt)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        if let notes = release.body, !notes.isEmpty {
                                            Text(notes)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .padding(.top, 2)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $selectedRelease) { release in
            releaseDetailsSheetView(for: release)
        }
    }

    private var disconnectedPlaceholder: some View {
        GitHubEmptyStateView(
            title: "No Repository Associated",
            description: "A GitHub repository must first be associated with this project to view and manage Releases.",
            systemImage: "shippingbox",
            accentColor: .orange,
            actionTitle: "Configure Repository Association"
        ) {
            RepositoryContext.shared.showingSetRepoSheet = true
        }
    }

    // MARK: - Release Detail Modal sheet

    private func releaseDetailsSheetView(for release: GitHubReleaseInfo) -> some View {
        VStack(spacing: 0) {
            // Sheet Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(release.name ?? release.tagName)
                        .font(.title2.bold())
                    Text("Tag: \(release.tagName) • Published on \(release.createdAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    selectedRelease = nil
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Sheet Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Release Notes section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Release Notes")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(release.body ?? "No release notes provided.")
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(6)
                    }

                    Divider()

                    // Assets list segment
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Binary Assets & Distributions")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            assetRow(name: "SwiftCode-\(release.tagName)-macOS.dmg", size: "18.2 MB")
                            assetRow(name: "Source code (zip)", size: "4.5 MB")
                            assetRow(name: "Source code (tar.gz)", size: "4.1 MB")
                        }
                    }

                    // Reference Links section
                    if let htmlUrlStr = release.htmlUrl, let htmlURL = URL(string: htmlUrlStr) {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reference Links")
                                .font(.headline)

                            Link(destination: htmlURL) {
                                HStack {
                                    Image(systemName: "safari")
                                    Text("Open Release on GitHub")
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                }
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 550, height: 500)
    }

    private func assetRow(name: String, size: String) -> some View {
        HStack {
            Image(systemName: "shippingbox")
                .foregroundStyle(.green)
            Text(name)
                .font(.system(size: 11, design: .monospaced))
            Spacer()
            Text(size)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Download") {
                // Mock download
            }
            .buttonStyle(.plain)
            .font(.caption2.bold())
            .foregroundStyle(Color.accentColor)
        }
        .padding(6)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(4)
    }

    // MARK: - Draft Release Sheet

    private var draftReleaseSheetView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Draft New Release").font(.headline)
                Spacer()
                Button("Cancel") { showDraftSheet = false }
                    .buttonStyle(.bordered)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tag Version Name")
                        .font(.subheadline.bold())
                    TextField("e.g. v1.0.0", text: $draftTag)
                        .textFieldStyle(.roundedBorder)

                    Text("Release Title")
                        .font(.subheadline.bold())
                    TextField("e.g. v1.0.0 - Stable compilation", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Release Notes").font(.subheadline.bold())
                        Spacer()
                        Button {
                            generateAIReleaseNotes()
                        } label: {
                            Label(isGeneratingAINotes ? "Generating..." : "Generate with AI", systemImage: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.purple)
                        .disabled(isGeneratingAINotes)
                    }

                    TextEditor(text: $draftNotes)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 150)
                        .border(Color.secondary.opacity(0.2), width: 1)
                }
                .padding()
            }

            Button {
                executePublishDraft()
            } label: {
                Text("Publish Release")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(draftTag.isEmpty || draftTitle.isEmpty || isPublishingDraft)
        }
        .padding(24)
        .frame(width: 480, height: 500)
    }

    // MARK: - Actions Operations Executions

    private func fetchReleases() {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        let urlStr: String
        if context.displayMode == .entireAccount {
            if let (owner, repo) = ownerAndRepo {
                urlStr = "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=10"
            } else {
                releases = []
                return
            }
        } else if let (owner, repo) = ownerAndRepo {
            urlStr = "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=10"
        } else {
            releases = []
            return
        }

        isFetching = true
        Task {
            do {
                guard let url = URL(string: urlStr) else { return }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                self.releases = try JSONDecoder().decode([GitHubReleaseInfo].self, from: data)
            } catch {
                errorMessage = "Failed to load releases: \(error.localizedDescription)"
                showError = true
            }
            isFetching = false
        }
    }

    private func executePublishDraft() {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty,
              let (owner, repo) = ownerAndRepo else { return }

        isPublishingDraft = true
        Task {
            do {
                let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let body: [String: Any] = [
                    "tag_name": draftTag,
                    "name": draftTitle,
                    "body": draftNotes,
                    "draft": false,
                    "prerelease": false
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                    successMessage = "Release successfully published on GitHub!"
                    showSuccess = true
                    fetchReleases()
                    showDraftSheet = false
                    draftTag = ""
                    draftTitle = ""
                    draftNotes = ""
                } else {
                    let errStr = String(data: data, encoding: .utf8) ?? "Unknown HTTP error"
                    errorMessage = "Failed to publish release: \(errStr)"
                    showError = true
                }
            } catch {
                errorMessage = "Failed to publish: \(error.localizedDescription)"
                showError = true
            }
            isPublishingDraft = false
        }
    }

    private func generateAIReleaseNotes() {
        isGeneratingAINotes = true
        draftNotes = ""

        let prompt = """
        You are an AI DevOps engineer writing high quality release notes for our project.
        - Proposed Tag: \(draftTag)
        - Title: \(draftTitle)

        Generate a beautiful Markdown release notes draft containing:
        - ## 🚀 What's New: A clear bullet list of major additions.
        - ## 🛠️ Improvements & Fixes: Standard bug fixes list.
        - ## 👥 Contributors: Mentioning Jules and review team.
        Make it clean, brief and engaging.
        """

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                draftNotes = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                draftNotes = "AI failed: \(error.localizedDescription)"
            }
            isGeneratingAINotes = false
        }
    }
}
