import SwiftUI

struct WorkflowEditorView: View {
    @Binding var content: String
    let fileName: String
    let onSave: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(fileName)
                    .font(.headline)
                Spacer()
                Button("Save") {
                    onSave(content)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .padding()
        }
    }
}
