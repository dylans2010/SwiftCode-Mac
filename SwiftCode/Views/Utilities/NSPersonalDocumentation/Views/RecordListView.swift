import SwiftUI

struct RecordListView: View {
    let coordinator: PersonalDocumentationCoordinator
    let kind: ModuleKind
    @Binding var selectedDocumentID: UUID?

    @State private var documents: [Document] = []

    // Search, Filter, Sort States
    @State private var searchQuery = ""
    @State private var categoryFilter = "All"
    @State private var sortOption: SortOption = .updatedAt

    // Creation States
    @State private var showingAddAlert = false
    @State private var newDocTitle = ""
    @State private var newDocKind: ModuleKind = .personalDocumentation

    enum SortOption: String, CaseIterable, Identifiable {
        case updatedAt = "Recently Updated"
        case createdAt = "Date Created"
        case title = "Title"

        var id: String { rawValue }
    }

    private var creationKinds: [ModuleKind] {
        ModuleKind.allCases.filter {
            $0.archetype == .freeform || $0.archetype == .structured
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with unified actions
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.rawValue)
                        .font(.headline)
                    Text("\(filteredAndSortedDocuments.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    newDocKind = (kind.archetype == .freeform || kind.archetype == .structured) ? kind : .personalDocumentation
                    showingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create new document")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Filters & Search Panel
            VStack(spacing: 8) {
                // Search Bar
                NativeSearchField(text: $searchQuery, placeholder: "Search title...")

                HStack(spacing: 8) {
                    // Category Filter
                    Picker("Filter", selection: $categoryFilter) {
                        Text("All Types").tag("All")
                        ForEach(creationKinds) { cKind in
                            Text(cKind.rawValue).tag(cKind.rawValue)
                        }
                    }
                    .controlSize(.small)
                    .labelsHidden()

                    // Sort Option
                    Picker("Sort", selection: $sortOption) {
                        ForEach(SortOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .controlSize(.small)
                    .labelsHidden()
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Document List
            if filteredAndSortedDocuments.isEmpty {
                ContentUnavailableView {
                    Label(searchQuery.isEmpty ? "No Documents" : "No Results", systemImage: "doc.text")
                } description: {
                    Text(searchQuery.isEmpty ? "Create a document to get started." : "No documents match your query.")
                }
            } else {
                List(filteredAndSortedDocuments, id: \.id, selection: $selectedDocumentID) { doc in
                    HStack(spacing: 10) {
                        Image(systemName: doc.moduleKind.icon)
                            .foregroundStyle(doc.moduleKind.accentColor)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(doc.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack {
                                Text(doc.moduleKind.rawValue)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text("•")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                Text(doc.updatedAt, style: .date)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tag(doc.id)
                    .contextMenu {
                        Button {
                            duplicateDocument(doc)
                        } label: {
                            Label("Duplicate Document", systemImage: "doc.on.doc")
                        }

                        Button(role: .destructive) {
                            deleteDocument(doc)
                        } label: {
                            Label("Delete Document", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onAppear {
            loadDocuments()
            // Sync active sidebar selected kind as initial filter, unless it's general/derived
            if kind.archetype == .freeform || kind.archetype == .structured {
                categoryFilter = kind.rawValue
            } else {
                categoryFilter = "All"
            }
        }
        .onChange(of: kind) { _, _ in
            loadDocuments()
            if kind.archetype == .freeform || kind.archetype == .structured {
                categoryFilter = kind.rawValue
            } else {
                categoryFilter = "All"
            }
        }
        .sheet(isPresented: $showingAddAlert) {
            VStack(spacing: 16) {
                Text("New Document Creation")
                    .font(.headline)

                TextField("Document Title", text: $newDocTitle)
                    .textFieldStyle(.roundedBorder)

                Picker("Document Type", selection: $newDocKind) {
                    ForEach(creationKinds) { cKind in
                        Text(cKind.rawValue).tag(cKind)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Cancel") {
                        showingAddAlert = false
                    }
                    Button("Create") {
                        if !newDocTitle.isEmpty {
                            let newDoc = try? coordinator.documents.createDocument(title: newDocTitle, kind: newDocKind)
                            loadDocuments()
                            selectedDocumentID = newDoc?.id
                            showingAddAlert = false
                            newDocTitle = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newDocTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 320)
        }
    }

    private var filteredAndSortedDocuments: [Document] {
        var filtered = documents

        // 1. Search Query Filter
        if !searchQuery.isEmpty {
            filtered = filtered.filter { doc in
                doc.title.localizedCaseInsensitiveContains(searchQuery) ||
                doc.markdownSource.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        // 2. Category Filter
        if categoryFilter != "All" {
            filtered = filtered.filter { $0.moduleKind.rawValue == categoryFilter }
        }

        // 3. Sort
        switch sortOption {
        case .updatedAt:
            filtered.sort { $0.updatedAt > $1.updatedAt }
        case .createdAt:
            filtered.sort { $0.createdAt > $1.createdAt }
        case .title:
            filtered.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }

        return filtered
    }

    private func loadDocuments() {
        // If sidebar is a specific archetype, load that. If it's containers/organizers, show all or filtered.
        if kind.archetype == .freeform || kind.archetype == .structured {
            documents = (try? coordinator.documents.fetchDocuments(for: kind)) ?? []
        } else {
            // General or organizer, load all documents for browsing
            documents = (try? coordinator.documents.fetchDocuments()) ?? []
        }
    }

    private func duplicateDocument(_ doc: Document) {
        do {
            // Copy fields cleanly and save
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

            loadDocuments()
            selectedDocumentID = duplicate.id
        } catch {
            // silent catch
        }
    }

    private func deleteDocument(_ doc: Document) {
        do {
            try coordinator.documents.deleteDocument(doc)
            if selectedDocumentID == doc.id {
                selectedDocumentID = nil
            }
            loadDocuments()
        } catch {
            // silent catch
        }
    }
}
