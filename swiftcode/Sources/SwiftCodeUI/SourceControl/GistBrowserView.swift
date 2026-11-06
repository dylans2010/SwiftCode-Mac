import SwiftUI
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeIDECore

/// The gist browser: the authenticated user's gists and starred
/// gists, one gist's files with editing, comments, revisions, and a
/// line diff between a revision and the current file.
///
/// This is the port of Legacy's whole Gists surface
/// (`SwiftCode/Views/Gists/GistsView.swift`, `GistDetailView.swift`,
/// `CreateGistView.swift`, `GistDiffView.swift`,
/// `GistRevisionsView.swift`, `Components/GistRowView.swift`,
/// `GistCommentSectionView.swift`, `GistFileEditorView.swift`,
/// `GistFileTabBar.swift`, `MarkdownToolbar.swift`): the same flows,
/// rebuilt in SwiftCode style (default accent, no Legacy orange) on the
/// new `GitHubGistClient`. There was no gist surface in SwiftCode at
/// all — no client, no UI.
///
/// The token comes from the secret store (`SecretAccount.githubToken`,
/// set in Settings > Accounts). Without one the browser shows an
/// honest "sign in" state instead of fake gists. Hosting and menu
/// wiring are on the integration list: this view is presented with
/// `NSHostingController`, as `SettingsPanes.swift` already does for
/// `PaywallView`.
@MainActor
struct GistBrowserView: View {
    @State private var model = GistBrowserModel()
    @State private var scope = GistScope.mine
    @State private var showingCreate = false
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Gists", selection: $scope) {
                    Text("Mine").tag(GistScope.mine)
                    Text("Starred").tag(GistScope.starred)
                }
                .pickerStyle(.segmented)
                .padding(8)
                Group {
                    if model.isLoading {
                        ProgressView()
                    } else if let errorMessage = model.errorMessage {
                        ContentUnavailableView("Could not load gists", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    } else if !model.tokenAvailable {
                        ContentUnavailableView("Sign in to see gists", systemImage: "person.crop.circle.badge.questionmark", description: Text("Gists need a GitHub token. Add one in Settings > Accounts."))
                    } else if model.gists.isEmpty {
                        ContentUnavailableView("No gists", systemImage: "doc.text")
                    } else {
                        List(model.gists) { gist in
                            NavigationLink(value: gist.id) {
                                GistRowView(gist: gist, isStarred: model.starredIDs.contains(gist.id))
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { gistId in
                GistDetailView(model: model, gistId: gistId)
            }
            .toolbar {
                Button("New Gist") { showingCreate = true }
                    .disabled(!model.tokenAvailable)
                Button("Refresh") { Task { await model.load(scope: scope) } }
            }
            .sheet(isPresented: $showingCreate) {
                GistCreateView(model: model)
            }
            .task {
                model.refreshToken()
                await model.load(scope: scope)
            }
            .onChange(of: scope) { _, newScope in
                Task { await model.load(scope: newScope) }
            }
        }
    }
}

enum GistScope: Hashable {
    case mine, starred
}

/// The gist browser's state. Each load reads the token fresh from
/// the secret store, so signing in (or out) in Settings > Accounts
/// takes effect on the next refresh without relaunching.
@Observable
@MainActor
final class GistBrowserModel {
    var gists: [GitHubGist] = []
    var starredIDs: Set<String> = []
    var isLoading = false
    var errorMessage: String?
    var tokenAvailable = false

    private var token: String? {
        let raw = CodingAssistantServices.shared.store.readString(SecretAccount.githubToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.flatMap { $0.isEmpty ? nil : $0 }
    }

    func refreshToken() {
        tokenAvailable = token != nil
    }

    func client() -> GitHubGistClient {
        let token = token
        return GitHubGistClient(tokenProvider: { token })
    }

    func load(scope: GistScope) async {
        refreshToken()
        guard tokenAvailable else { gists = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch scope {
            case .mine:
                gists = try await client().listGists()
            case .starred:
                gists = try await client().listStarredGists()
            }
            starredIDs = Set(await withTaskGroup(of: String?.self) { group in
                // The client is hoisted out: the group tasks are
                // nonisolated, so they cannot capture the
                // MainActor-isolated model.
                let gistClient = self.client()
                for gist in gists {
                    group.addTask {
                        (try? await gistClient.isStarred(id: gist.id)) == true ? gist.id : nil
                    }
                }
                var ids: Set<String> = []
                for await id in group {
                    if let id { ids.insert(id) }
                }
                return ids
            })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchGist(id: String) async -> GitHubGist? {
        return try? await client().fetchGist(id: id)
    }

    func deleteGist(id: String) async -> Bool {
        do {
            try await client().deleteGist(id: id)
            gists.removeAll { $0.id == id }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setStarred(id: String, starred: Bool) async {
        do {
            if starred {
                try await client().starGist(id: id)
                starredIDs.insert(id)
            } else {
                try await client().unstarGist(id: id)
                starredIDs.remove(id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createGist(description: String?, isPublic: Bool, files: [String: String]) async -> GitHubGist? {
        do {
            let gist = try await client().createGist(description: description, isPublic: isPublic, files: files)
            gists.insert(gist, at: 0)
            return gist
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

private struct GistRowView: View {
    var gist: GitHubGist
    var isStarred: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if isStarred {
                    Image(systemName: "star.fill").font(.caption)
                }
                Text(gist.description ?? gist.sortedFiles.first?.filename ?? "Untitled gist")
                    .lineLimit(1)
                Spacer()
                if !gist.isPublic {
                    Text("Secret").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(gist.sortedFiles.map(\.filename).joined(separator: ", "))
                if let updated = gist.updatedAt {
                    Text(updated, style: .relative)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

private struct GistDetailView: View {
    var model: GistBrowserModel
    var gistId: String
    @State private var gist: GitHubGist?
    @State private var selectedFile: String?
    @State private var editedContent = ""
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var comments: [GitHubGistComment] = []
    @State private var newComment = ""
    @State private var revisions: [GitHubGistRevision] = []
    @State private var selectedRevision: GitHubGistRevision?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let gist {
                List {
                    Section {
                        Text(gist.description ?? "Untitled gist").font(.headline)
                        HStack {
                            Text(gist.isPublic ? "Public" : "Secret")
                            if let owner = gist.owner?.login { Text(owner) }
                            if let updated = gist.updatedAt { Text(updated, style: .date) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Section("Files") {
                        Picker("File", selection: $selectedFile) {
                            ForEach(gist.sortedFiles) { file in
                                Text(file.filename).tag(Optional(file.filename))
                            }
                        }
                        .pickerStyle(.segmented)
                        if let filename = selectedFile ?? gist.sortedFiles.first?.filename,
                           let file = gist.files[filename] {
                            if isEditing {
                                TextEditor(text: $editedContent)
                                    .frame(minHeight: 200)
                                    .font(.body.monospaced())
                            } else {
                                Text(file.content ?? "Content loads when the gist is opened.")
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                            }
                            HStack {
                                if isEditing {
                                    Button("Cancel") {
                                        isEditing = false
                                        editedContent = file.content ?? ""
                                    }
                                    Button("Save") {
                                        Task {
                                            isSaving = true
                                            defer { isSaving = false }
                                            let updated = try? await model.client().updateGist(
                                                id: gist.id,
                                                description: nil,
                                                files: [filename: editedContent])
                                            if let updated {
                                                self.gist = updated
                                                isEditing = false
                                            }
                                        }
                                    }
                                    .disabled(isSaving)
                                } else {
                                    Button("Edit") {
                                        editedContent = file.content ?? ""
                                        isEditing = true
                                    }
                                }
                                Spacer()
                                Button("Delete Gist", role: .destructive) {
                                    Task {
                                        if await model.deleteGist(id: gist.id) {
                                            dismiss()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Section("Comments") {
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(comment.user?.login ?? "Unknown").font(.caption).foregroundStyle(.secondary)
                                Text(comment.body)
                            }
                        }
                        HStack {
                            TextField("Add a comment", text: $newComment)
                            Button("Post") {
                                Task {
                                    if let posted = try? await model.client().createComment(gistId: gist.id, body: newComment) {
                                        comments.append(posted)
                                        newComment = ""
                                    }
                                }
                            }
                            .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Section("Revisions") {
                        ForEach(revisions) { revision in
                            Button {
                                selectedRevision = revision
                            } label: {
                                HStack {
                                    Text(String(revision.version.prefix(7)))
                                    Spacer()
                                    if let user = revision.user?.login { Text(user).font(.caption) }
                                    if let date = revision.committedAt {
                                        Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .sheet(item: $selectedRevision) { revision in
                    GistDiffView(gist: gist, revision: revision, client: model.client())
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Gist")
        .toolbar {
            if let gist {
                Button(model.starredIDs.contains(gist.id) ? "Unstar" : "Star") {
                    Task { await model.setStarred(id: gist.id, starred: !model.starredIDs.contains(gist.id)) }
                }
            }
        }
        .task {
            gist = await model.fetchGist(id: gistId)
            if let gist {
                selectedFile = gist.sortedFiles.first?.filename
                comments = (try? await model.client().fetchComments(gistId: gist.id)) ?? []
                revisions = gist.history
            }
        }
    }
}

private struct GistCreateView: View {
    var model: GistBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var isPublic = false
    @State private var filename = ""
    @State private var content = ""
    @State private var files: [String: String] = [:]

    var body: some View {
        Form {
            TextField("Description", text: $description)
            Toggle("Public", isOn: $isPublic)
            Section("Files") {
                ForEach(Array(files.keys.sorted()), id: \.self) { name in
                    Text(name)
                }
                HStack {
                    TextField("Filename", text: $filename)
                    Button("Add File") {
                        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        files[name] = content
                        filename = ""
                        content = ""
                    }
                    .disabled(filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                TextEditor(text: $content)
                    .frame(minHeight: 120)
                    .font(.body.monospaced())
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Gist") {
                    Task {
                        if await model.createGist(
                            description: description.isEmpty ? nil : description,
                            isPublic: isPublic,
                            files: files) != nil {
                            dismiss()
                        }
                    }
                }
                .disabled(files.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 420)
    }
}

/// The diff between one revision and the current file contents,
/// computed with SwiftCode's Myers diff (`MyersDiff`): added lines in
/// green, removed lines in red, unchanged lines plain. The revision
/// is fetched live (`GET /gists/{id}/{sha}`); nothing is fabricated.
private struct GistDiffView: View {
    var gist: GitHubGist
    var revision: GitHubGistRevision
    var client: GitHubGistClient
    @State private var oldGist: GitHubGist?
    @State private var selectedFile: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let oldGist, let filename = selectedFile ?? gist.sortedFiles.first?.filename {
                    let oldText = oldGist.files[filename]?.content ?? ""
                    let newText = gist.files[filename]?.content ?? ""
                    let result = MyersDiff.diff(old: MyersDiff.lines(of: oldText), new: MyersDiff.lines(of: newText))
                    List {
                        Picker("File", selection: $selectedFile) {
                            ForEach(gist.sortedFiles) { file in
                                Text(file.filename).tag(Optional(file.filename))
                            }
                        }
                        .pickerStyle(.segmented)
                        ForEach(Array(result.operations.enumerated()), id: \.offset) { _, operation in
                            switch operation {
                            case .equal(let line):
                                Text(line).font(.body.monospaced())
                            case .delete(let line):
                                Text(line).font(.body.monospaced())
                                    .foregroundStyle(.red)
                            case .insert(let line):
                                Text(line).font(.body.monospaced())
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .navigationTitle("Revision \(String(revision.version.prefix(7)))")
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                Button("Done") { dismiss() }
            }
            .task {
                oldGist = try? await client.fetchGistAtRevision(id: gist.id, sha: revision.version)
                selectedFile = gist.sortedFiles.first?.filename
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}
