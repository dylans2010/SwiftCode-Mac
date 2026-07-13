import SwiftUI

struct RecordDetailView: View {
    let coordinator: PersonalDocumentationCoordinator
    let documentID: UUID?

    @State private var document: Document? = nil

    var body: some View {
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
                                        set: { doc.status = $0; try? coordinator.documents.updateDocument(doc) }
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
                                        set: { doc.priority = $0; try? coordinator.documents.updateDocument(doc) }
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
                                .frame(height: 250)
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
        .onAppear {
            loadDocument()
        }
        .onChange(of: documentID) { _, _ in
            loadDocument()
        }
    }

    private func loadDocument() {
        if let id = documentID {
            document = try? coordinator.documents.fetchDocument(id: id)
        } else {
            document = nil
        }
    }
}
