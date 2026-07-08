import SwiftUI

struct GistDetailView: View {
    @State var gistId: String
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    @State private var gist: GistResponse?
    @State private var isEditing = false
    @State private var editableDescription = ""
    @State private var editableFiles: [GistFile] = []
    @State private var selectedFileID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if let currentGist = gist {
                headerView(currentGist)

                GistFileTabBar(
                    files: editableFiles,
                    selectedFileID: $selectedFileID,
                    isEditing: isEditing,
                    onRemoveFile: { id in
                        editableFiles.removeAll { $0.id == id }
                    }
                )

                if let selectedFileIndex = editableFiles.firstIndex(where: { $0.id == selectedFileID }) {
                    GistFileEditorView(file: $editableFiles[selectedFileIndex], isEditing: isEditing)
                } else {
                    ContentUnavailableView("Select a file", systemImage: "doc.text")
                }
            } else {
                ProgressView("Loading Gist...")
            }
        }
        .navigationTitle("Gist Details")
        .toolbar {
            ToolbarItem {
                HStack {
                    if isEditing {
                        Button("Save") {
                            Task { await saveGist() }
                        }
                        .bold()
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
            }
        }
        .task {
            await loadGist()
        }
    }

    private func headerView(_ currentGist: GistResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextField("Description", text: $editableDescription)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(currentGist.description ?? "No description")
                    .font(.title3.bold())
            }

            HStack {
                Text(currentGist.owner?.login ?? "anonymous")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Updated \(currentGist.updatedAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
    }

    private func loadGist() async {
        do {
            let fetched = try await gistService.fetchGist(id: gistId)
            self.gist = fetched
            self.editableDescription = fetched.description ?? ""
            self.editableFiles = fetched.files.values.sorted { $0.filename < $1.filename }
            self.selectedFileID = editableFiles.first?.id
        } catch {
            print("Failed to load gist: \(error)")
        }
    }

    private func saveGist() async {
        guard let currentGist = gist else { return }
        var fileUpdates: [String: GistUpdateRequest.FileUpdateContent?] = [:]
        for file in editableFiles {
            fileUpdates[file.filename] = GistUpdateRequest.FileUpdateContent(content: file.content)
        }
        do {
            let updated = try await gistService.updateGist(id: gistId, description: editableDescription, files: fileUpdates)
            self.gist = updated
            self.isEditing = false
            await loadGist()
        } catch {
            print("Failed to update gist: \(error)")
        }
    }
}
