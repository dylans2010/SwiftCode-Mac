import SwiftUI

struct JSMinifierView: View {
    @State private var input = "function hello() {\n  console.log(\"Hello world\");\n}"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Minify JS") { minify() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()

            HSplitView {
                TextEditor(text: $input)
                TextEditor(text: .constant(output))
            }
        }
        .navigationTitle("JS Minifier")
    }

    func minify() {
        output = input.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s*([\\{\\}\\(\\)=,;])\\s*", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
