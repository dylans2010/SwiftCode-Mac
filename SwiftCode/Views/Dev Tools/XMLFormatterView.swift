import SwiftUI

struct XMLFormatterView: View {
    @State private var input = "<root><item id=\"1\">Hello</item><item id=\"2\">World</item></root>"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Format XML") { format() }
                Button("Minify XML") { minify() }
                Spacer()
            }
            .padding()

            HSplitView {
                TextEditor(text: $input)
                    .font(.system(.body, design: .monospaced))
                TextEditor(text: .constant(output))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("XML Formatter")
    }

    func format() {
        // Basic indentation-based XML formatter
        var result = ""
        var level = 0
        let tokens = input.replacingOccurrences(of: ">", with: ">\n").replacingOccurrences(of: "<", with: "\n<").components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        for token in tokens {
            let t = token.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("</") {
                level -= 1
                result += String(repeating: "  ", count: level) + t + "\n"
            } else if t.hasPrefix("<") && !t.hasSuffix("/>") && !t.contains("</") {
                result += String(repeating: "  ", count: level) + t + "\n"
                level += 1
            } else {
                result += String(repeating: "  ", count: level) + t + "\n"
            }
        }
        output = result
    }

    func minify() {
        output = input.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
