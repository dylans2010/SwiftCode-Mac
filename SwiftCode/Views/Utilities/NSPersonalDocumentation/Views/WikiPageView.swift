import SwiftUI

// MARK: - WIKI PAGE LIST VIEW (PANEL 2)
struct WikiPageListView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var wikiPages: [WikiPage] = []
    @State private var showingAddPageSheet = false
    @State private var newPageTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wiki Pages")
                        .font(.headline)
                    Text("\(wikiPages.count) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingAddPageSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Wiki Page")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if wikiPages.isEmpty {
                ContentUnavailableView("No Pages", systemImage: "book.pages")
                    .frame(maxHeight: .infinity)
            } else {
                List(wikiPages, id: \.id, selection: Binding(
                    get: { coordinator.selectedWikiPageID },
                    set: { coordinator.selectedWikiPageID = $0 }
                )) { page in
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.purple)
                        Text(page.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .tag(page.id)
                    .padding(.vertical, 4)
                }
                .listStyle(.sidebar)
            }
        }
        .onAppear {
            loadPages()
        }
        .sheet(isPresented: $showingAddPageSheet) {
            VStack(spacing: 16) {
                Text("New Wiki Page")
                    .font(.headline)
                TextField("Page Title", text: $newPageTitle)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") {
                        showingAddPageSheet = false
                    }
                    Button("Create") {
                        if !newPageTitle.isEmpty {
                            let newPage = try? coordinator.wiki.createOrUpdateWikiPage(title: newPageTitle, content: "# \(newPageTitle)\n\nStart writing wiki content here.")
                            loadPages()
                            coordinator.selectedWikiPageID = newPage?.id
                            showingAddPageSheet = false
                            newPageTitle = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }

    private func loadPages() {
        wikiPages = (try? coordinator.wiki.fetchWikiPages()) ?? []
        if coordinator.selectedWikiPageID == nil {
            coordinator.selectedWikiPageID = wikiPages.first?.id
        }
    }
}

// MARK: - WIKI PAGE DETAIL VIEW (PANEL 3)
struct WikiPageDetailView: View {
    let coordinator: PersonalDocumentationCoordinator
    @State private var page: WikiPage? = nil
    @State private var contentEditorText = ""
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            if let page = page {
                HStack {
                    Image(systemName: "globe.americas.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    Text(page.title)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Picker("Mode", selection: $isEditing) {
                        Text("Read").tag(false)
                        Text("Edit").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)

                    if isEditing {
                        Button {
                            page.markdownSource = contentEditorText
                            try? coordinator.wiki.createOrUpdateWikiPage(title: page.title, content: contentEditorText)
                            isEditing = false
                        } label: {
                            Text("Save Page")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                if isEditing {
                    DocNSTextView(text: $contentEditorText)
                        .padding(24)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if page.markdownSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("This wiki page is empty. Click 'Edit' to start writing.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            } else {
                                MarkdownBlockListView(blocks: MarkdownRenderer.shared.parse(page.markdownSource))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No page selected", systemImage: "globe")
                } description: {
                    Text("Select a page from the Wiki list or add a new overview page.")
                }
            }
        }
        .onAppear {
            loadPage()
        }
        .onChange(of: coordinator.selectedWikiPageID) { _, _ in
            loadPage()
            isEditing = false
        }
    }

    private func loadPage() {
        if let id = coordinator.selectedWikiPageID,
           let pages = try? coordinator.wiki.fetchWikiPages(),
           let match = pages.first(where: { $0.id == id }) {
            self.page = match
            self.contentEditorText = match.markdownSource
        } else {
            self.page = nil
            self.contentEditorText = ""
        }
    }
}

// Deprecated old container
struct WikiPageView: View {
    let coordinator: PersonalDocumentationCoordinator

    var body: some View {
        HSplitView {
            WikiPageListView(coordinator: coordinator)
                .frame(width: 250)
            WikiPageDetailView(coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
