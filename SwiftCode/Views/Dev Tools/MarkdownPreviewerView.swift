import SwiftUI

struct MarkdownPreviewerView: View {
    @State private var markdownInput = "# Hello World\n\nThis is a **markdown** previewer.\n\n* Item 1\n* Item 2"

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("Markdown Editor")
                    .font(.caption)
                    .padding([.top, .leading])
                TextEditor(text: $markdownInput)
                    .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading) {
                Text("Preview")
                    .font(.caption)
                    .padding([.top, .leading])
                ScrollView {
                    if let attributedString = try? AttributedString(markdown: markdownInput) {
                        Text(attributedString)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    } else {
                        Text(markdownInput)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
        }
        .navigationTitle("Markdown Preview")
    }
}
