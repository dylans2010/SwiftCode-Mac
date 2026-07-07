import SwiftUI

struct XMLToJSONView: View {
    @State private var xmlInput = "<root>\n  <item id=\"1\">Hello</item>\n  <item id=\"2\">World</item>\n</root>"
    @State private var jsonOutput = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Convert XML to JSON") { convert() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $xmlInput)
                    .font(.system(.body, design: .monospaced))
                TextEditor(text: .constant(jsonOutput))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("XML to JSON")
    }

    func convert() {
        // Simplified XML to JSON logic for demonstration
        var dict: [String: Any] = [:]
        let lines = xmlInput.components(separatedBy: .newlines)

        for line in lines {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("<") && l.contains(">") && l.contains("</") {
                let key = l.components(separatedBy: CharacterSet(charactersIn: "<>"))[1]
                let value = l.components(separatedBy: CharacterSet(charactersIn: "<>"))[2]
                dict[key] = value
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            jsonOutput = string
        } else {
            jsonOutput = "Could not parse simple XML."
        }
    }
}
