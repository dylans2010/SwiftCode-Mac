import SwiftUI

struct RecordListView: View {
    let coordinator: PersonalDocumentationCoordinator
    let kind: ModuleKind
    @Binding var selectedDocumentID: UUID?

    @State private var documents: [Document] = []
    @State private var showingAddAlert = false
    @State private var newDocTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(kind.rawValue)
                    .font(.headline)

                Spacer()

                Button {
                    showingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(documents, id: \.id, selection: $selectedDocumentID) { doc in
                NavigationLink(value: doc.id) {
                    HStack {
                        Image(systemName: kind.icon)
                            .foregroundStyle(kind.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.title)
                                .font(.body.bold())
                            Text("Updated \(doc.updatedAt, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tag(doc.id)
            }
            .listStyle(.sidebar)
        }
        .onAppear {
            loadDocuments()
        }
        .onChange(of: kind) { _, _ in
            loadDocuments()
        }
        .sheet(isPresented: $showingAddAlert) {
            VStack(spacing: 16) {
                Text("New \(kind.rawValue) Item")
                    .font(.headline)
                TextField("Title", text: $newDocTitle)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") {
                        showingAddAlert = false
                    }
                    Button("Create") {
                        if !newDocTitle.isEmpty {
                            let newDoc = try? coordinator.documents.createDocument(title: newDocTitle, kind: kind)
                            loadDocuments()
                            selectedDocumentID = newDoc?.id
                            showingAddAlert = false
                            newDocTitle = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }

    private func loadDocuments() {
        documents = (try? coordinator.documents.fetchDocuments(for: kind)) ?? []
    }
}
