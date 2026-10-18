import SwiftUI
import AppKit

/// Native macOS browser for Assist Markdown artifacts.
///
/// Lists every artifact in the native store (`.assist_temp/artifacts/`,
/// plus workspace-root `agent_notes.md`) with human-readable display
/// titles — never raw filenames as the primary title — and renders the
/// selected artifact's Markdown.
public struct AssistArtifactsView: View {
    @Bindable private var store = AssistArtifactStore.shared

    @State private var selection: UUID?
    @State private var detailContent: String = ""
    @State private var detailError: String?
    @State private var isLoadingDetail = false
    @State private var isConfirmingDelete = false
    /// The last artifact id logged to AssistUserActionLog, so refreshes
    /// don't double-log the same open.
    @State private var lastLoggedArtifactID: UUID?

    public init() {}

    private var workspaceRoot: URL? {
        ProjectSessionStore.shared.activeProject?.directoryURL
            ?? store.currentWorkspaceRoot
    }

    private var selectedRecord: AssistArtifactRecord? {
        guard let selection else { return nil }
        return store.records.first(where: { $0.id == selection })
    }

    private var selectedFileURL: URL? {
        guard let record = selectedRecord, let root = workspaceRoot else { return nil }
        return root.appendingPathComponent(record.relativePath)
    }

    /// `agent_notes.md` is protected: the store refuses to delete it.
    private var canDeleteSelected: Bool {
        guard let record = selectedRecord else { return false }
        return record.filename != "agent_notes.md"
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 700, minHeight: 480)
        .background(.background)
        .onAppear(perform: refresh)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let fileURL = selectedFileURL {
                    ShareLink(item: fileURL)
                        .help("Share artifact")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copySelectedPath()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Copy artifact path")
                .disabled(selectedFileURL == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    revealSelectedInFinder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal in Finder")
                .disabled(selectedFileURL == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete artifact")
                .disabled(!canDeleteSelected)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh artifacts")
            }
        }
        .alert("Delete Artifact?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                deleteSelectedArtifact()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("'\(selectedRecord?.title ?? "this artifact")' will be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Group {
            if store.records.isEmpty {
                ContentUnavailableView(
                    "No Artifacts",
                    systemImage: "doc.richtext",
                    description: Text("Durable deliverables — reports, analyses, plans — appear here when Assist saves them with the artifact workflow.")
                )
            } else {
                List(store.records, selection: $selection) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            // Display title is primary; filename is never the title.
                            Text(record.title)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(record.kind.displayName)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        if !record.description.isEmpty {
                            Text(record.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(record.modifiedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .tag(record.id)
                }
            }
        }
        .navigationTitle("Artifacts")
        .onChange(of: selection) { _, newValue in
            loadDetail(for: newValue)
        }
        .onAppear {
            if selection == nil, let first = store.records.first {
                selection = first.id
            }
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if isLoadingDetail {
                ProgressView("Loading artifact…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detailError {
                ContentUnavailableView(
                    "Couldn't Read Artifact",
                    systemImage: "exclamationmark.triangle",
                    description: Text(detailError)
                )
            } else if detailContent.isEmpty {
                ContentUnavailableView(
                    "Select an Artifact",
                    systemImage: "doc.richtext",
                    description: Text("Choose an artifact from the list to read it.")
                )
            } else {
                ScrollView {
                    renderedMarkdown(detailContent)
                        .textSelection(.enabled)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func renderedMarkdown(_ markdown: String) -> Text {
        // Full interpreted syntax so headings, tables, lists, and code
        // fences mandated by the artifacts guidelines actually render.
        if let attributed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) {
            return Text(attributed)
        }
        return Text(markdown)
    }

    // MARK: - Loading

    private func refresh() {
        guard let root = workspaceRoot else { return }
        store.refresh(workspaceRoot: root)
        if selection == nil, let first = store.records.first {
            selection = first.id
        } else if let selection, !store.records.contains(where: { $0.id == selection }) {
            self.selection = store.records.first?.id
        }
        loadDetail(for: selection)
    }

    private func loadDetail(for id: UUID?) {
        detailContent = ""
        detailError = nil
        guard let id,
              let record = store.records.first(where: { $0.id == id }),
              let root = workspaceRoot else { return }
        isLoadingDetail = true
        // AssistArtifactStore is @MainActor; read synchronously on the main actor.
        Task { @MainActor in
            defer { isLoadingDetail = false }
            do {
                let (record, content, _) = try store.readArtifact(name: record.filename, workspaceRoot: root)
                detailContent = content
                if lastLoggedArtifactID != record.id {
                    lastLoggedArtifactID = record.id
                    AssistUserActionLog.record(.artifactOpened(artifactID: record.id, title: record.title))
                }
            } catch {
                detailError = error.localizedDescription
            }
        }
    }

    // MARK: - Toolbar actions

    private func copySelectedPath() {
        guard let url = selectedFileURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    private func revealSelectedInFinder() {
        guard let url = selectedFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func deleteSelectedArtifact() {
        guard let record = selectedRecord, let root = workspaceRoot else { return }
        do {
            _ = try store.deleteArtifact(name: record.filename, workspaceRoot: root)
            selection = store.records.first?.id
            loadDetail(for: selection)
        } catch {
            detailError = error.localizedDescription
        }
    }
}
