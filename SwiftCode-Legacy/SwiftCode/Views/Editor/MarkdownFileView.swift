import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Views.Editor", category: "MarkdownFileView")

struct MarkdownFileView: View {
    @Bindable var viewModel: EditorViewModel
    let fileURL: URL

    @State private var markdownText = ""
    @State private var viewMode: ViewMode = .split
    @State private var isDirty = false
    @State private var lastSavedContent = ""
    @State private var showTableBuilder = false
    @State private var tableRows = 3
    @State private var tableCols = 3

    private enum ViewMode: String, CaseIterable, Identifiable {
        case edit = "Edit"
        case preview = "Preview"
        case split = "Split"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            formatToolbar
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

            Divider()

            HSplitView {
                if viewMode == .edit || viewMode == .split {
                    TextEditor(text: $markdownText)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .onChange(of: markdownText) { _, newValue in
                            isDirty = newValue != lastSavedContent
                            viewModel.updateContent(newValue)
                        }
                        .frame(minWidth: 200)
                }

                if viewMode == .preview || viewMode == .split {
                    ScrollView {
                        MarkdownBlockListView(blocks: MarkdownRenderer.shared.parse(markdownText))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .frame(minWidth: 200)
                }
            }
        }
        .onAppear {
            loadContent()
        }
        .sheet(isPresented: $showTableBuilder) {
            tableBuilderSheet
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                HStack(spacing: 8) {
                    Picker("View Mode", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    if isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                            .help("Unsaved Changes")
                    }

                    Button {
                        saveContent()
                    } label: {
                        Text("Save")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isDirty)
                }
            }
        }
    }

    private var formatToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Group {
                    Button { insertText("**", suffix: "**") } label: { Image(systemName: "bold") }.help("Bold")
                    Button { insertText("_", suffix: "_") } label: { Image(systemName: "italic") }.help("Italic")
                    Button { insertText("~~", suffix: "~~") } label: { Image(systemName: "strikethrough") }.help("Strikethrough")
                    Button { insertText("`", suffix: "`") } label: { Image(systemName: "code") }.help("Inline Code")
                }

                Divider().frame(height: 16)

                Group {
                    Button { insertText("```swift\n", suffix: "\n```") } label: { Label("Code Block", systemImage: "curlybraces") }.help("Code Block")
                    Button { insertText("# ", suffix: "") } label: { Text("H1").bold() }.help("Heading 1")
                    Button { insertText("## ", suffix: "") } label: { Text("H2").bold() }.help("Heading 2")
                    Button { insertText("### ", suffix: "") } label: { Text("H3").bold() }.help("Heading 3")
                    Button { insertText("> ", suffix: "") } label: { Image(systemName: "quote.opening") }.help("Block Quote")
                }

                Divider().frame(height: 16)

                Group {
                    Button { insertText("- ", suffix: "") } label: { Image(systemName: "list.bullet") }.help("Unordered List")
                    Button { insertText("1. ", suffix: "") } label: { Image(systemName: "list.number") }.help("Ordered List")
                    Button { insertText("- [ ] ", suffix: "") } label: { Image(systemName: "checkmark.square") }.help("Checklist")
                }

                Divider().frame(height: 16)

                Group {
                    Button { insertText("[", suffix: "](https://)") } label: { Image(systemName: "link") }.help("Link")
                    Button { insertText("![", suffix: "](image.png)") } label: { Image(systemName: "photo") }.help("Image")
                    Button { insertText("\n---\n", suffix: "") } label: { Image(systemName: "minus") }.help("Horizontal Rule")
                    Button { showTableBuilder = true } label: { Image(systemName: "tablecells") }.help("Build Table")
                }
            }
        }
    }

    private func insertText(_ prefix: String, suffix: String) {
        markdownText.append("\(prefix)text\(suffix)")
        isDirty = true
    }

    private var tableBuilderSheet: some View {
        VStack(spacing: 16) {
            Text("Create Markdown Table")
                .font(.headline)

            Stepper("Columns: \(tableCols)", value: $tableCols, in: 1...10)
            Stepper("Rows: \(tableRows)", value: $tableRows, in: 1...20)

            HStack {
                Button("Cancel") {
                    showTableBuilder = false
                }
                Spacer()
                Button("Generate") {
                    generateTable()
                    showTableBuilder = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 250, height: 180)
    }

    private func generateTable() {
        var tableStr = "\n"
        tableStr += "|"
        for i in 1...tableCols {
            tableStr += " Column \(i) |"
        }
        tableStr += "\n|"
        for _ in 1...tableCols {
            tableStr += "---|"
        }
        tableStr += "\n"
        for r in 1...tableRows {
            tableStr += "|"
            for c in 1...tableCols {
                tableStr += " Row \(r) Col \(c) |"
            }
            tableStr += "\n"
        }
        markdownText.append(tableStr)
        isDirty = true
    }

    private func loadContent() {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            markdownText = content
            lastSavedContent = content
            isDirty = false
        } catch {
            logger.error("Failed to load markdown: \(error.localizedDescription)")
        }
    }

    private func saveContent() {
        do {
            try markdownText.write(to: fileURL, atomically: true, encoding: .utf8)
            lastSavedContent = markdownText
            isDirty = false
            viewModel.activeDocument?.isDirty = false
            logger.info("Successfully saved markdown content.")
        } catch {
            logger.error("Failed to save markdown content: \(error.localizedDescription)")
        }
    }
}
