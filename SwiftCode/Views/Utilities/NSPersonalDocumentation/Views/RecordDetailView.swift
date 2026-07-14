import SwiftUI

struct RecordDetailView: View {
    let coordinator: PersonalDocumentationCoordinator
    let documentID: UUID?

    @State private var document: Document? = nil
    @State private var relationships: [Relationship] = []
    @State private var versions: [DocumentVersion] = []

    // Header controls
    @State private var viewMode: ViewMode = .read
    @State private var isRenaming = false
    @State private var editTitleText = ""
    @State private var showBrowserSheet = false

    // Relationship formulation states
    @State private var showAddLink = false
    @State private var targetName = ""
    @State private var targetType = "Swift File"

    // Versioning states
    @State private var selectedVersion: DocumentVersion? = nil

    // Delete Confirmation
    @State private var showingDeleteConfirmation = false

    enum ViewMode: String, CaseIterable, Identifiable {
        case read = "Read Mode"
        case edit = "Edit Mode"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let doc = document {
                // Document Header Bar
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        // Editable Title or Header Info
                        HStack(spacing: 8) {
                            Image(systemName: doc.moduleKind.icon)
                                .font(.title2)
                                .foregroundStyle(doc.moduleKind.accentColor)

                            if isRenaming {
                                TextField("Document Title", text: $editTitleText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.title3.bold())
                                    .frame(maxWidth: 300)
                                    .onSubmit {
                                        renameDocument(to: editTitleText)
                                    }

                                Button {
                                    renameDocument(to: editTitleText)
                                } label: {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    isRenaming = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(doc.title)
                                    .font(.title2.bold())
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .textSelection(.enabled)

                                Button {
                                    editTitleText = doc.title
                                    isRenaming = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer()

                        // Read / Edit Segmented View Control
                        Picker("View Mode", selection: $viewMode) {
                            ForEach(ViewMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode == .read ? "eye.fill" : "pencil")
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)

                        // Quick Action Buttons
                        HStack(spacing: 12) {
                            Button {
                                showBrowserSheet = true
                            } label: {
                                Label("Browse", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                            .help("Open Document Browser")

                            Button {
                                duplicateDocument()
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .help("Duplicate Document")
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("Delete Document")
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()
                }

                // Content Area
                if doc.archetype == "freeform" && viewMode == .edit {
                    PersonalDocCanvasView(coordinator: coordinator, doc: doc)
                } else if viewMode == .edit {
                    // EDIT MODE: No outer ScrollView wrapper to eliminate nested scrolling conflict
                    VStack(alignment: .leading, spacing: 20) {
                        // Unified attributes grid for structured records or meta display
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            GridRow {
                                Text("Status")
                                    .font(.subheadline.bold())
                                Picker("Status", selection: Binding(
                                    get: { doc.status ?? "To Do" },
                                    set: { doc.status = $0; try? coordinator.documents.updateDocument(doc); reloadData() }
                                )) {
                                    Text("To Do").tag("To Do")
                                    Text("In Progress").tag("In Progress")
                                    Text("Done").tag("Done")
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                            }

                            GridRow {
                                Text("Priority")
                                    .font(.subheadline.bold())
                                Picker("Priority", selection: Binding(
                                    get: { doc.priority ?? "Medium" },
                                    set: { doc.priority = $0; try? coordinator.documents.updateDocument(doc); reloadData() }
                                )) {
                                    Text("High").tag("High")
                                    Text("Medium").tag("Medium")
                                    Text("Low").tag("Low")
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Markdown Source Notes")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            DocNSTextView(text: Binding(
                                get: { doc.markdownSource },
                                set: { doc.markdownSource = $0; try? coordinator.documents.updateDocument(doc) }
                            ))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                        }
                    }
                    .padding(24)
                } else {
                    // READ MODE: High Fidelity Markdown rendering inside ScrollView
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Unified attributes grid for structured records or meta display
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                                GridRow {
                                    Text("Status")
                                        .font(.subheadline.bold())
                                    Picker("Status", selection: Binding(
                                        get: { doc.status ?? "To Do" },
                                        set: { doc.status = $0; try? coordinator.documents.updateDocument(doc); reloadData() }
                                    )) {
                                        Text("To Do").tag("To Do")
                                        Text("In Progress").tag("In Progress")
                                        Text("Done").tag("Done")
                                    }
                                    .pickerStyle(.menu)
                                    .controlSize(.small)
                                }

                                GridRow {
                                    Text("Priority")
                                        .font(.subheadline.bold())
                                    Picker("Priority", selection: Binding(
                                        get: { doc.priority ?? "Medium" },
                                        set: { doc.priority = $0; try? coordinator.documents.updateDocument(doc); reloadData() }
                                    )) {
                                        Text("High").tag("High")
                                        Text("Medium").tag("Medium")
                                        Text("Low").tag("Low")
                                    }
                                    .pickerStyle(.menu)
                                    .controlSize(.small)
                                }
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 12) {
                                if doc.markdownSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("No content written in this document yet. Click 'Edit Mode' above to start writing markdown notes.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                } else {
                                    MarkdownBlockListView(blocks: MarkdownRenderer.shared.parse(doc.markdownSource))
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Item Selected", systemImage: "doc.text")
                } description: {
                    VStack(spacing: 12) {
                        Text("Select a document or record from the list, or open the browser to choose or create one.")
                        Button("Open Document Browser") {
                            showBrowserSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reloadData()
            // Observe the restored notification
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("PersonalDocDocumentRestored"),
                object: nil,
                queue: .main
            ) { _ in
                reloadData()
            }
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("PersonalDocViewModeChanged"),
                object: nil,
                queue: .main
            ) { notification in
                if let isEdit = notification.userInfo?["isEdit"] as? Bool {
                    viewMode = isEdit ? .edit : .read
                }
            }
        }
        .onChange(of: documentID) { _, _ in
            reloadData()
            isRenaming = false
        }
        .sheet(isPresented: $showBrowserSheet) {
            VStack(spacing: 0) {
                HStack {
                    Text("Browse Documents")
                        .font(.headline)
                    Spacer()
                    Button("Close") {
                        showBrowserSheet = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                Divider()
                RecordListView(
                    coordinator: coordinator,
                    kind: document?.moduleKind ?? coordinator.selectedModuleKind ?? .personalDocumentation,
                    selectedDocumentID: Binding(
                        get: { coordinator.selectedDocumentID },
                        set: { coordinator.selectedDocumentID = $0 }
                    ),
                    onSelect: {
                        showBrowserSheet = false
                    }
                )
                .frame(width: 500, height: 600)
            }
        }
        .sheet(isPresented: $showAddLink) {
            VStack(spacing: 16) {
                Text("Link to Project Resource")
                    .font(.headline)

                TextField("Resource Name (e.g. main.swift, SHA hash, etc.)", text: $targetName)
                    .textFieldStyle(.roundedBorder)

                Picker("Resource Type", selection: $targetType) {
                    Text("Swift File").tag("Swift File")
                    Text("Git Commit").tag("Git Commit")
                    Text("Bug Database").tag("Bug Database")
                    Text("Milestone").tag("Milestone")
                    Text("UML Diagram").tag("UML Diagram")
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Cancel") {
                        showAddLink = false
                    }
                    Button("Link") {
                        if let doc = document, !targetName.isEmpty {
                            try? coordinator.relationships.addLink(
                                sourceID: doc.id,
                                targetType: targetType,
                                targetIdentifier: UUID().uuidString,
                                targetName: targetName
                            )
                            targetName = ""
                            showAddLink = false
                            reloadData()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 320)
        }
        .sheet(item: $selectedVersion) { ver in
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Compare Document Revision")
                        .font(.title3.bold())
                    Spacer()
                    Button("Close") {
                        selectedVersion = nil
                    }
                }

                Divider()

                HSplitView {
                    VStack(alignment: .leading) {
                        Text("Selected Historical Version (\(ver.timestamp, style: .time))")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(ver.markdownSnapshot)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(6)
                    }

                    VStack(alignment: .leading) {
                        Text("Current Workspace Version")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(document?.markdownSource ?? "")
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(6)
                    }
                }

                HStack {
                    Spacer()
                    Button("Restore Selected Revision") {
                        if let doc = document {
                            doc.markdownSource = ver.markdownSnapshot
                            doc.title = ver.titleSnapshot
                            try? coordinator.documents.updateDocument(doc)
                            selectedVersion = nil
                            reloadData()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 750, height: 500)
        }
        .alert("Are you sure you want to delete this document?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteDocument()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func reloadData() {
        if let id = documentID {
            document = try? coordinator.documents.fetchDocument(id: id)
            if let doc = document {
                relationships = (try? coordinator.relationships.fetchRelationships(for: doc.id)) ?? []
                versions = (try? coordinator.versionHistory.fetchVersions(for: doc.id)) ?? []
            }
        } else {
            document = nil
            relationships = []
            versions = []
        }
    }

    // MARK: - Actions Helper

    private func renameDocument(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let doc = document, !trimmed.isEmpty else { return }
        doc.title = trimmed
        try? coordinator.documents.updateDocument(doc)
        isRenaming = false
        reloadData()
    }

    private func duplicateDocument() {
        guard let doc = document else { return }
        do {
            let duplicate = Document(
                projectID: doc.projectID,
                archetype: doc.archetype,
                moduleKind: doc.moduleKind,
                title: "\(doc.title) Copy",
                markdownSource: doc.markdownSource,
                attachments: doc.attachments,
                tags: doc.tags,
                createdAt: Date(),
                updatedAt: Date(),
                pinned: doc.pinned,
                archived: doc.archived
            )
            duplicate.status = doc.status
            duplicate.priority = doc.priority
            duplicate.severity = doc.severity
            duplicate.reproSteps = doc.reproSteps
            duplicate.stackTrace = doc.stackTrace
            duplicate.targetQuarter = doc.targetQuarter
            duplicate.dependencyIDs = doc.dependencyIDs

            coordinator.storage.context.insert(duplicate)
            try coordinator.storage.context.save()

            coordinator.selectedDocumentID = duplicate.id
            reloadData()
        } catch {
            // silent catch
        }
    }

    private func deleteDocument() {
        guard let doc = document else { return }
        do {
            try coordinator.documents.deleteDocument(doc)
            coordinator.selectedDocumentID = nil
            reloadData()
        } catch {
            // silent catch
        }
    }
}
