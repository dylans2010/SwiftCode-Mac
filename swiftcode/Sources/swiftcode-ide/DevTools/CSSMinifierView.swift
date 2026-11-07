import SwiftUI

struct CSSMinifierView: View {
    @State private var input = "body {\n  color: #333;\n  margin: 0;\n}\n\n.container {\n  padding: 20px;\n}"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Minify CSS") { minify() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $input)
                TextEditor(text: .constant(output))
            }
        }
        .navigationTitle("CSS Minifier")
    }

    func minify() {
        output = input
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s*([\\{\\}:;])\\s*", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
