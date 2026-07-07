import SwiftUI

struct MarkdownPreviewerView: View {
    @State private var markdownInput = "# Hello Markdown\n\nThis is a **preview** of your markdown.\n\n- List item 1\n- List item 2\n\n```swift\nlet x = 10\n```"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    Text("Markdown Source")
                        .font(.headline)
                        .padding([.top, .leading])
                    TextEditor(text: $markdownInput)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }

                Divider()

                VStack(alignment: .leading) {
                    Text("Preview")
                        .font(.headline)
                        .padding([.top, .leading])

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            // Simple mock preview using standard SwiftUI components
                            // In a real app, use a proper Markdown library or WebView
                            Text("Mock Preview of:").font(.caption)
                            Text(markdownInput)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("Markdown Previewer")
    }
}
