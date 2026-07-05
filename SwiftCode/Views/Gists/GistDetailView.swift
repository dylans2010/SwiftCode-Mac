import SwiftUI
import UniformTypeIdentifiers

struct GistDetailView: View {
    @State var gistId: String
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    @State private var gist: GistResponse?
    @State private var isEditing = false
    @State private var editableDescription = ""
    @State private var editableFiles: [GistFile] = []
    @State private var selectedFileID: UUID?
    @State private var showDeleteFileConfirmation = false
    @State private var fileIDToDelete: UUID?
    @State private var showComments = false
    @State private var showRevisions = false
    @State private var showImportPicker = false
    @State private var importedFilesCount = 0
    @State private var showZIPDownloadProgress = false
    @State private var downloadedZIPURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea()

                if let currentGist = gist {
                    VStack(spacing: 0) {
                        headerView(currentGist)

                        GistFileTabBar(
                            files: editableFiles,
                            selectedFileID: $selectedFileID,
                            isEditing: isEditing,
                            onRemoveFile: { id in
                                fileIDToDelete = id
                                showDeleteFileConfirmation = true
                            }
                        )

                        if let selectedFileIndex = editableFiles.firstIndex(where: { $0.id == selectedFileID }) {
                            GistFileEditorView(file: $editableFiles[selectedFileIndex], isEditing: isEditing)
                        } else {
                            Text("Select a file to view content")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } else {
                    ProgressView("Fetching Gist details...")
                }
            }
            .navigationTitle(isEditing ? "Editing Gist" : "Gist Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if isEditing {
                            Button("Save") {
                                Task { await saveGist() }
                            }
                            .bold()
                        } else {
                            Menu {
                                Button { isEditing = true } label: { Label("Edit", systemImage: "pencil") }
                                Button { addFile() } label: { Label("Add File", systemImage: "plus") }
                                Divider()
                                Button { copyLink() } label: { Label("Copy Link", systemImage: "link") }
                                Button { openInBrowser() } label: { Label("Open in Browser", systemImage: "safari") }
                                Button { forkGist() } label: { Label("Fork", systemImage: "arrow.branch") }
                                Button { showRevisions = true } label: { Label("Revisions", systemImage: "clock.arrow.circlepath") }
                                Button { showComments = true } label: { Label("Comments", systemImage: "bubble.left.and.bubble.right") }

                                Divider()

                                Menu("Clone") {
                                    Button { copyCloneURL(isSSH: false) } label: { Label("Clone via HTTPS", systemImage: "link") }
                                    Button { copyCloneURL(isSSH: true) } label: { Label("Clone via SSH", systemImage: "terminal") }
                                    Divider()
                                    Button { openCloneURL(isSSH: false) } label: { Label("Open HTTPS Remote", systemImage: "safari") }
                                    Button { openCloneURL(isSSH: true) } label: { Label("Open SSH Remote", systemImage: "terminal.fill") }
                                }

                                Button { copyEmbedCode() } label: { Label("Embed", systemImage: "chevron.left.forwardslash.chevron.right") }
                                Button { downloadZIP() } label: { Label("Download ZIP", systemImage: "archivebox") }
                                Divider()
                                Button { addFile() } label: { Label("Add Empty File", systemImage: "doc.badge.plus") }
                                Button { showImportPicker = true } label: { Label("Import Files/Folders", systemImage: "folder.badge.plus") }

                                if let urlString = gist?.htmlUrl, let url = URL(string: urlString) {
                                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showComments) {
                NavigationStack {
                    GistCommentSectionView(gistId: gistId)
                        .navigationTitle("Comments")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showComments = false }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showImportPicker) {
                FileImporterRepresentableView(
                    allowedContentTypes: [.item, .folder],
                    allowsMultipleSelection: true
                ) { urls in
                    showImportPicker = false
                    guard !urls.isEmpty else { return }
                    Task { await importFiles(urls) }
                }
                .ignoresSafeArea()
            }
            .alert("Delete File", isPresented: $showDeleteFileConfirmation) {
                Button("Delete", role: .destructive) {
                    if let id = fileIDToDelete {
                        removeFile(id: id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to remove this file from the Gist?")
            }
            .overlay {
                if let error = gistService.errorMessage {
                    errorBanner(message: error)
                }

                if importedFilesCount > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Text("Imported \(importedFilesCount) file(s) into this gist")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.85), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                        }
                        Spacer()
                    }
                }

                if showZIPDownloadProgress {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(.white)
                            Text("Downloading ZIP...")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .navigationDestination(isPresented: $showRevisions) {
                GistRevisionsView(gistId: gistId)
            }
        }
        .task {
            await loadGist()
        }
        .onChange(of: gistId) { _, _ in
            Task { await loadGist() }
        }
    }

    private func headerView(_ currentGist: GistResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                if isEditing {
                    TextField("Description (optional)", text: $editableDescription)
                        .font(.headline)
                        .padding(8)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(currentGist.description ?? "No description")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Spacer()

                Text(currentGist.public ? "Public" : "Secret")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(currentGist.public ? Color.green.opacity(0.2) : Color.secondary.opacity(0.2))
                    .foregroundStyle(currentGist.public ? .green : .secondary)
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                if let avatar = currentGist.owner?.avatarUrl, let url = URL(string: avatar) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                    } placeholder: {
                        Color.gray
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
                }

                Text(currentGist.owner?.login ?? "anonymous")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Updated \(currentGist.updatedAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
    }

    private func loadGist() async {
        do {
            let fetchedGist = try await gistService.fetchGist(id: gistId)
            let previousFilename = editableFiles.first { $0.id == selectedFileID }?.filename
            self.gist = fetchedGist
            self.editableDescription = fetchedGist.description ?? ""
            self.editableFiles = fetchedGist.files.values.sorted { $0.filename < $1.filename }

            if let prevName = previousFilename,
               let matchedFile = editableFiles.first(where: { $0.filename == prevName }) {
                self.selectedFileID = matchedFile.id
            } else {
                self.selectedFileID = editableFiles.first?.id
            }
        } catch {
            print("Failed to load gist: \(error)")
        }
    }

    private func saveGist() async {
        guard let currentGist = gist else { return }

        var fileUpdates: [String: GistUpdateRequest.FileUpdateContent?] = [:]

        // Identify updated and new files
        for file in editableFiles {
            let cleanedName = file.filename.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedName.isEmpty else { continue }

            let originalFile = currentGist.files[cleanedName]
            if originalFile == nil || originalFile?.content != file.content {
                fileUpdates[cleanedName] = GistUpdateRequest.FileUpdateContent(content: file.content)
            }
        }

        // Identify deleted files
        for originalFilename in currentGist.files.keys {
            if !editableFiles.contains(where: { $0.filename == originalFilename }) {
                fileUpdates[originalFilename] = nil
            }
        }

        do {
            let updated = try await gistService.updateGist(id: gistId, description: editableDescription, files: fileUpdates)
            self.gist = updated
            self.isEditing = false
            await loadGist() // Refresh to ensure state consistency
        } catch {
            print("Failed to update gist: \(error)")
        }
    }

    private func addFile() {
        let newFile = GistFile(filename: "", content: "")
        editableFiles.append(newFile)
        selectedFileID = newFile.id
        isEditing = true
    }

    private func removeFile(id: UUID) {
        editableFiles.removeAll { $0.id == id }
        if selectedFileID == id {
            selectedFileID = editableFiles.first?.id
        }
    }

    private func copyLink() {
        UIPasteboard.general.string = gist?.htmlUrl
    }

    private func openInBrowser() {
        if let urlStr = gist?.htmlUrl, let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }

    private func forkGist() {
        Task {
            if let forked = try? await gistService.forkGist(id: gistId) {
                self.gistId = forked.id
                await loadGist()
            }
        }
    }

    private func copyCloneURL(isSSH: Bool) {
        guard let currentGist = gist else { return }
        let cloneURL = gistService.cloneURL(for: currentGist, useSSH: isSSH)
        UIPasteboard.general.string = cloneURL
    }

    private func openCloneURL(isSSH: Bool) {
        guard let currentGist = gist else { return }
        let cloneString = gistService.cloneURL(for: currentGist, useSSH: isSSH)

        if isSSH {
            UIPasteboard.general.string = cloneString
            return
        }

        if let url = URL(string: cloneString) {
            UIApplication.shared.open(url)
        }
    }

    private func copyEmbedCode() {
        guard let currentGist = gist, let owner = currentGist.owner?.login else { return }
        let embedCode = "<script src=\"https://gist.github.com/\(owner)/\(currentGist.id).js\"></script>"
        UIPasteboard.general.string = embedCode
    }

    private func downloadZIP() {
        showZIPDownloadProgress = true
        Task {
            do {
                let url = try await gistService.downloadGistZip(gistId: gistId)
                showZIPDownloadProgress = false
                downloadedZIPURL = url

                DispatchQueue.main.async {
                    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {

                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = rootVC.view
                            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                            popover.permittedArrowDirections = []
                        }

                        rootVC.present(activityVC, animated: true)
                    }
                }
            } catch {
                showZIPDownloadProgress = false
                print("Failed to download ZIP: \(error)")
            }
        }
    }

    private func importFiles(_ urls: [URL]) async {
        do {
            let updated = try await gistService.uploadFilesToGist(id: gistId, urls: urls)
            gist = updated
            editableDescription = updated.description ?? ""
            editableFiles = updated.files.values.sorted { $0.filename < $1.filename }
            selectedFileID = editableFiles.first?.id
            importedFilesCount = urls.count

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                importedFilesCount = 0
            }
        } catch {
            print("Failed to import files: \(error)")
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.subheadline)
                .padding()
                .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
