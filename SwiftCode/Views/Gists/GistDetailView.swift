import SwiftUI

struct GistDetailView: View {
    @State var gistId: String
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    var onDismiss: () -> Void

    @State private var gist: GistResponse?
    @State private var isEditing = false
    @State private var editableDescription = ""
    @State private var editableFiles: [GistFile] = []
    @State private var openFileIDs: Set<UUID> = []
    @State private var selectedFileID: UUID?
    @State private var showRevisions = false

    var body: some View {
        VStack(spacing: 0) {
            // Premium Header Actions Row
            HStack(spacing: 16) {
                Button {
                    handleDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.bold)
                        Text("Gist Index")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)

                Spacer()

                Label("Interactive Gist Workspace", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.orange)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        showRevisions = true
                    } label: {
                        Label("Revisions", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    if isEditing {
                        Button("Save Changes") {
                            Task { await saveGist() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    } else {
                        Button("Edit Gist") {
                            isEditing = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if let currentGist = gist {
                HSplitView {
                    // Left Column: Gist Metadata & Navigator
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Metadata Group
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Label("Metadata", systemImage: "info.circle.fill")
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                        Spacer()
                                    }

                                    if isEditing {
                                        TextField("Description", text: $editableDescription)
                                            .textFieldStyle(.roundedBorder)
                                    } else {
                                        Text(currentGist.description ?? "No description available")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }

                                    Divider()

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Owner:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(currentGist.owner?.login ?? "anonymous")
                                                .font(.caption.bold())
                                        }

                                        HStack {
                                            Text("Updated:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(currentGist.updatedAt.formatted())
                                                .font(.caption)
                                        }
                                    }
                                }
                                .padding(8)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            // File Navigator Group
                            GroupBox {
                                renderFileNavigator()
                                    .padding(8)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                        .padding(20)
                    }
                    .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    // Right Column: Tabbed Editor Workspace
                    VStack(spacing: 0) {
                        // Multi-file Workspace Tab Bar
                        renderWorkspaceTabBar()

                        Divider()

                        if let selectedID = selectedFileID,
                           let selectedFileIndex = editableFiles.firstIndex(where: { $0.id == selectedID }) {
                            GistFileEditorView(file: $editableFiles[selectedFileIndex], isEditing: isEditing)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            VStack(spacing: 16) {
                                Spacer()
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text("No Active Tabs Open")
                                    .font(.title3.bold())
                                Text("Select a file from the navigator on the left to open it in a workspace tab.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 300)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor.controlBackgroundColor))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack {
                    Spacer()
                    ProgressView("Retrieving Gist specifications...")
                        .controlSize(.large)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showRevisions) {
            GistRevisionsView(gistId: gistId)
                .environmentObject(gistService)
        }
        .task {
            await loadGist()
        }
    }

    @ViewBuilder
    private func renderWorkspaceTabBar() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                let openFiles = editableFiles.filter { openFileIDs.contains($0.id) }
                ForEach(openFiles) { file in
                    let isActive = selectedFileID == file.id
                    HStack(spacing: 6) {
                        Button {
                            selectedFileID = file.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.caption)
                                    .foregroundColor(isActive ? .orange : .secondary)
                                Text(file.filename.isEmpty ? "Untitled" : file.filename)
                                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                                    .foregroundStyle(isActive ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            closeTab(file.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .background(Color.clear)
                        .clipShape(Circle())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isActive ? Color.secondary.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .background(Color.secondary.opacity(0.04))
    }

    @ViewBuilder
    private func renderFileNavigator() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Files in Gist", systemImage: "folder.fill")
                .font(.headline)
                .foregroundColor(.orange)

            ForEach(editableFiles) { file in
                let isOpen = openFileIDs.contains(file.id)
                Button {
                    openFileIDs.insert(file.id)
                    selectedFileID = file.id
                } label: {
                    HStack {
                        Image(systemName: isOpen ? "doc.text.fill" : "doc.text")
                            .foregroundColor(.orange)
                        Text(file.filename)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        if isOpen {
                            Text("Open")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                        } else {
                            Text("Tab")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func closeTab(_ id: UUID) {
        openFileIDs.remove(id)
        if selectedFileID == id {
            selectedFileID = editableFiles.first { openFileIDs.contains($0.id) }?.id
        }
    }

    private func handleDismiss() {
        onDismiss()
        dismiss()
    }

    private func loadGist() async {
        do {
            let fetched = try await gistService.fetchGist(id: gistId)
            self.gist = fetched
            self.editableDescription = fetched.description ?? ""
            self.editableFiles = fetched.files.values.sorted { $0.filename < $1.filename }
            self.openFileIDs = Set(editableFiles.map { $0.id })
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
