import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import SwiftCodeAssistant

public struct AssistArtifactsView: View {
    @Bindable private var store = AssistArtifactStore.shared

    @State private var selection: UUID?
    @State private var detailContent: String = ""
    @State private var detailError: String?
    @State private var isLoadingDetail = false
    @State private var isConfirmingDelete = false
    @State private var viewMode: ArtifactViewMode = .rendered
    @State private var lastLoggedArtifactID: UUID?

    public enum ArtifactViewMode: String, CaseIterable, Identifiable {
        case rendered = "Rendered"
        case source = "Source"

        public var id: String { rawValue }
    }

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
                VStack(spacing: 0) {
                    if let record = selectedRecord {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(record.title)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                    Text(record.kind.displayName)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }
                                if !record.description.isEmpty {
                                    Text(record.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Picker("Mode", selection: $viewMode) {
                                ForEach(ArtifactViewMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 170)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.thinMaterial)
                        Divider()
                    }

                    ScrollView {
                        if viewMode == .rendered {
                            let blocks = MarkdownParser.shared.parse(detailContent)
                            MarkdownBlockListView(blocks: blocks, showsLineNumbers: true)
                                .textSelection(.enabled)
                                .padding(24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(detailContent)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

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
