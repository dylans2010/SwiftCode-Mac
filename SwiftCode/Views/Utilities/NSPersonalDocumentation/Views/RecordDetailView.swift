import SwiftUI

struct RecordDetailView: View {
    let coordinator: PersonalDocumentationCoordinator
    let documentID: UUID?

    @State private var document: Document? = nil
    @State private var relationships: [Relationship] = []
    @State private var versions: [DocumentVersion] = []

    // Relationship formulation states
    @State private var showAddLink = false
    @State private var targetName = ""
    @State private var targetType = "Swift File"

    // Versioning states
    @State private var selectedVersion: DocumentVersion? = nil

    var body: some View {
        HSplitView {
            // Main Document Content
            VStack(spacing: 0) {
                if let doc = document {
                    if doc.archetype == "freeform" {
                        PersonalDocCanvasView(coordinator: coordinator, doc: doc)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(doc.title)
                                    .font(.title.bold())

                                Divider()

                                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                                    GridRow {
                                        Text("Status")
                                            .bold()
                                        Picker("Status", selection: Binding(
                                            get: { doc.status ?? "To Do" },
                                            set: { doc.status = $0; try? coordinator.documents.updateDocument(doc); reloadData() }
                                        )) {
                                            Text("To Do").tag("To Do")
                                            Text("In Progress").tag("In Progress")
                                            Text("Done").tag("Done")
                                        }
                                        .pickerStyle(.menu)
                                    }

                                    GridRow {
                                        Text("Priority")
                                            .bold()
                                        Picker("Priority", selection: Binding(
                                            get: { doc.priority ?? "Medium" },
                                            set: { doc.priority = $0; try? coordinator.documents.updateDocument(doc); reloadData() }
                                        )) {
                                            Text("High").tag("High")
                                            Text("Medium").tag("Medium")
                                            Text("Low").tag("Low")
                                        }
                                        .pickerStyle(.menu)
                                    }
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Markdown Notes")
                                        .font(.headline)
                                    TextEditor(text: Binding(
                                        get: { doc.markdownSource },
                                        set: { doc.markdownSource = $0; try? coordinator.documents.updateDocument(doc) }
                                    ))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 350)
                                    .border(Color.secondary.opacity(0.2))
                                }
                            }
                            .padding(24)
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Item Selected", systemImage: "doc.text")
                    } description: {
                        Text("Select a document or record from the list to view and edit details.")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right Inspector Sidebar: Relationships & Version History
            if let doc = document {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            // Section 1: Document Relationships & Links
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Document Relationships")
                                        .font(.headline)
                                    Spacer()
                                    Button {
                                        showAddLink = true
                                    } label: {
                                        Image(systemName: "link.badge.plus")
                                    }
                                    .buttonStyle(.plain)
                                }

                                if relationships.isEmpty {
                                    Text("No connected resources. Link this document to Swift files, commits, bugs, or milestones.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(relationships) { rel in
                                            HStack {
                                                Image(systemName: "link")
                                                    .foregroundStyle(.blue)
                                                VStack(alignment: .leading) {
                                                    Text(rel.targetName)
                                                        .font(.caption.bold())
                                                    Text(rel.targetType)
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Button {
                                                    try? coordinator.relationships.removeLink(rel)
                                                    reloadData()
                                                } label: {
                                                    Image(systemName: "xmark.circle")
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(6)
                                            .background(Color(NSColor.controlBackgroundColor))
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)

                            Divider()

                            // Section 2: Revision History Versioning
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Document Versioning")
                                    .font(.headline)

                                Button("Save Current Snapshot") {
                                    try? coordinator.versionHistory.recordSnapshot(for: doc)
                                    reloadData()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                if versions.isEmpty {
                                    Text("No previous snapshots. Snapshots provide historical restoration points.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(versions) { ver in
                                            Button {
                                                selectedVersion = ver
                                            } label: {
                                                HStack {
                                                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                                    VStack(alignment: .leading) {
                                                        Text("Snapshot")
                                                            .font(.caption.bold())
                                                        Text(ver.timestamp, style: .time)
                                                            .font(.system(size: 9))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                }
                                                .padding(6)
                                                .background(selectedVersion?.id == ver.id ? Color.blue.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                                                .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)
                        }
                        .padding()
                    }
                }
                .frame(width: 250)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .onAppear {
            reloadData()
        }
        .onChange(of: documentID) { _, _ in
            reloadData()
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
}
