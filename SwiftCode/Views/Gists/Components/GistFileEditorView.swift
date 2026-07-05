import SwiftUI

struct GistFileEditorView: View {
    @Binding var file: GistFile
    var isEditing: Bool
    @State private var wordWrap = true
    @State private var showMarkdownPreview = false

    var isMarkdown: Bool {
        file.filename.lowercased().hasSuffix(".md") || file.filename.lowercased().hasSuffix(".markdown")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tiny filename header (only in non-edit mode, or for context)
            if isEditing {
                TextField("Filename (e.g. main.swift)", text: $file.filename)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.03))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    TextEditorRepresentable(
                        text: $file.content,
                        wordWrap: wordWrap,
                        searchQuery: "",
                        fileExtension: file.filename.components(separatedBy: ".").last ?? "swift"
                    )
                    .background(Color(red: 0.11, green: 0.11, blue: 0.14))
                    .disabled(!isEditing)

                    if showMarkdownPreview && isMarkdown {
                        Divider()
                        markdownPreview
                    }
                }

                if isMarkdown {
                    Button {
                        withAnimation {
                            showMarkdownPreview.toggle()
                        }
                    } label: {
                        Image(systemName: showMarkdownPreview ? "eye.slash" : "eye")
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(12)
                }
            }
        }
    }

    private var markdownPreview: some View {
        ScrollView {
            Text(parseMarkdown(file.content))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }

    private func parseMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
