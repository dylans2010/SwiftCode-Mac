import SwiftUI

struct PersonalDocCanvasView: View {
    let coordinator: PersonalDocumentationCoordinator
    @Bindable var doc: Document

    @State private var sourceText = ""
    @State private var isEditing = true
    @State private var wordCount = 0
    @State private var readingTimeSeconds = 0
    @State private var blocks: [MarkdownBlock] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Untitled Document", text: $doc.title)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .onChange(of: doc.title) { _, _ in
                        try? coordinator.documents.updateDocument(doc)
                    }

                Spacer()

                Picker("View", selection: $isEditing) {
                    Text("Editor").tag(true)
                    Text("Preview").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Button {
                    try? coordinator.versionHistory.recordSnapshot(for: doc)
                } label: {
                    Label("Save Revision", systemImage: "clock.badge.checkmark.fill")
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                if isEditing {
                    TextEditor(text: $sourceText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .onChange(of: sourceText) { _, newText in
                            doc.markdownSource = newText
                            try? coordinator.documents.updateDocument(doc)
                            updateMetrics()
                        }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            MarkdownBlockListView(blocks: blocks)
                        }
                        .padding(24)
                    }
                }
            }

            Divider()

            HStack {
                Label("\(wordCount) words", systemImage: "text.alignleft")
                Text("•")
                Label("\(readingTimeSeconds)s read time", systemImage: "clock")
                Spacer()
                Text("Last updated: \(doc.updatedAt, style: .time)")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .font(.caption)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            sourceText = doc.markdownSource
            updateMetrics()
        }
        .onChange(of: doc) { _, _ in
            sourceText = doc.markdownSource
            updateMetrics()
        }
    }

    private func updateMetrics() {
        let text = doc.markdownSource
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        wordCount = words.count
        readingTimeSeconds = max(1, Int(Double(wordCount) / 200.0 * 60.0))
        blocks = MarkdownRenderer.shared.parse(text)
    }
}
