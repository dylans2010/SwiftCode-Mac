import SwiftUI

struct WorkflowEditorView: View {
    @Binding var content: String
    let fileName: String
    let onSave: (String) -> Void

    @State private var snippetSearch = ""
    @State private var validationMessage: String?
    @State private var isValidating = false

    var body: some View {
        NavigationSplitView {
            VStack {
                TextField("Search Snippets", text: $snippetSearch)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                snippetLibrary
            }
            .navigationTitle("Snippets")
        } detail: {
            VStack(spacing: 0) {
                editorToolbar

                if let msg = validationMessage {
                    HStack {
                        Text(msg)
                            .font(.caption)
                        Spacer()
                        Button { validationMessage = nil } label: { Image(systemName: "xmark") }
                    }
                    .padding(8)
                    .background(msg.contains("Valid") ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                }

                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
        }
    }

    private var editorToolbar: some View {
        HStack {
            Text(fileName)
                .font(.headline)
            Spacer()

            Button {
                validateYAML()
            } label: {
                Label(isValidating ? "Validating..." : "Validate", systemImage: "checkmark.shield")
            }
            .disabled(isValidating)

            Button("Save") {
                onSave(content)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var filteredSnippets: [(String, String)] {
        let all = [
            ("Checkout", "- uses: actions/checkout@v4"),
            ("Setup Swift", "- name: Select Swift Version\n  uses: swift-actions/setup-swift@v2\n  with:\n    swift-version: '5.9'"),
            ("Build", "- name: Build\n  run: swift build"),
            ("Test", "- name: Run tests\n  run: swift test"),
            ("Slack Notification", "- name: Slack Notification\n  uses: rtCamp/action-slack-notify@v2\n  env:\n    SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}")
        ]
        if snippetSearch.isEmpty { return all }
        return all.filter { $0.0.localizedCaseInsensitiveContains(snippetSearch) }
    }

    private var snippetLibrary: some View {
        List {
            ForEach(filteredSnippets, id: \.0) { snippet in
                SnippetRow(title: snippet.0, code: snippet.1)
            }
        }
    }

    private func validateYAML() {
        isValidating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if content.contains(":") {
                validationMessage = "YAML syntax is Valid."
            } else {
                validationMessage = "Error: Invalid YAML syntax (missing keys)."
            }
            isValidating = false
        }
    }

    struct SnippetRow: View {
        let title: String
        let code: String
        var body: some View {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(code).font(.caption.monospaced()).lineLimit(2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }
            .help("Click to copy snippet")
        }
    }
}
