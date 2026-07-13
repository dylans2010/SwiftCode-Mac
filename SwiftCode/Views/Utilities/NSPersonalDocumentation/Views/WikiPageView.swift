import SwiftUI

struct WikiPageView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var wikiPages: [WikiPage] = []
    @State private var selectedPage: WikiPage? = nil
    @State private var showingAddPageSheet = false
    @State private var newPageTitle = ""
    @State private var contentEditorText = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Wiki Navigation")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingAddPageSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                Divider()

                List(wikiPages, id: \.id, selection: $selectedPage) { page in
                    NavigationLink(value: page) {
                        Label(page.title, systemImage: "book.pages")
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 200)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            VStack(spacing: 0) {
                if let page = selectedPage {
                    HStack {
                        Text(page.title)
                            .font(.title2.bold())
                        Spacer()
                        Button {
                            page.markdownSource = contentEditorText
                            try? coordinator.wiki.createOrUpdateWikiPage(title: page.title, content: contentEditorText)
                        } label: {
                            Text("Save Wiki Page")
                        }
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    TextEditor(text: $contentEditorText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                } else {
                    ContentUnavailableView {
                        Label("No page selected", systemImage: "globe")
                    } description: {
                        Text("Select a page from the Wiki navigation sidebar or add a new overview page.")
                    }
                }
            }
        }
        .onAppear {
            loadPages()
        }
        .onChange(of: selectedPage) { _, page in
            contentEditorText = page?.markdownSource ?? ""
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
                            selectedPage = newPage
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
        if selectedPage == nil {
            selectedPage = wikiPages.first
        }
    }
}
