import SwiftUI

struct SVGMinifierView: View {
    @State private var input = "<svg width=\"100\" height=\"100\">\n  <circle cx=\"50\" cy=\"50\" r=\"40\" stroke=\"black\" stroke-width=\"3\" fill=\"red\" />\n</svg>"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Minify SVG") { minify() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $input)
                TextEditor(text: .constant(output))
            }
        }
        .navigationTitle("SVG Minifier")
    }

    func minify() {
        output = input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined()
            .replacingOccurrences(of: " >", with: ">")
            .replacingOccurrences(of: "< ", with: "<")
    }
}
