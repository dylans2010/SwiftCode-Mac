import SwiftUI

struct HTMLMinifierView: View {
    @State private var input = "<html>\n  <body>\n    <h1>  Hello World  </h1>\n  </body>\n</html>"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Minify HTML") { minify() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $input)
                TextEditor(text: .constant(output))
            }
        }
        .navigationTitle("HTML Minifier")
    }

    func minify() {
        output = input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined()
    }
}
