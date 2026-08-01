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
    @State private var showRevisions = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let currentGist = gist {
                    // Gist Metadata & Description Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Gist Details", systemImage: "doc.text.magnifyingglass")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()

                                Button {
                                    showRevisions = true
                                } label: {
                                    Label("Revision History", systemImage: "clock.arrow.circlepath")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

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
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Files Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            GistFileTabBar(
                                files: editableFiles,
                                selectedFileID: $selectedFileID,
                                isEditing: isEditing,
                                onRemoveFile: { id in
                                    editableFiles.removeAll { $0.id == id }
                                }
                            )

                            Divider()

                            if let selectedFileIndex = editableFiles.firstIndex(where: { $0.id == selectedFileID }) {
                                GistFileEditorView(file: $editableFiles[selectedFileIndex], isEditing: isEditing)
                                    .frame(minHeight: 300)
                                    .cornerRadius(8)
                            } else {
                                ContentUnavailableView(
                                    "Select a file",
                                    systemImage: "doc.text",
                                    description: Text("Select a file from the tab bar above to edit its content.")
                                )
                                .frame(maxHeight: .infinity)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                } else {
                    Spacer()
                    ProgressView("Loading Gist...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Spacer()
                }
            }
            .padding(24)
            .navigationTitle("Gist Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        if isEditing {
                            Button("Save") {
                                Task { await saveGist() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        } else {
                            Button("Edit") {
                                isEditing = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 650)
        .sheet(isPresented: $showRevisions) {
            GistRevisionsView(gistId: gistId)
                .environmentObject(gistService)
        }
        .task {
            await loadGist()
        }
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
