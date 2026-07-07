import SwiftUI

struct TOMLToJSONView: View {
    @State private var tomlInput = "title = \"TOML Example\"\n[owner]\nname = \"Tom\"\nage = 30"
    @State private var jsonOutput = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Convert TOML to JSON") { convert() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $tomlInput)
                    .font(.system(.body, design: .monospaced))
                TextEditor(text: .constant(jsonOutput))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("TOML to JSON")
    }

    func convert() {
        var dict: [String: Any] = [:]
        let lines = tomlInput.components(separatedBy: .newlines)
        var currentSection = ""

        for line in lines {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") { continue }

            if l.hasPrefix("[") && l.hasSuffix("]") {
                currentSection = l.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                dict[currentSection] = [String: Any]()
            } else {
                let parts = l.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    let key = parts[0]
                    let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))

                    if currentSection.isEmpty {
                        dict[key] = value
                    } else if var sectionDict = dict[currentSection] as? [String: Any] {
                        sectionDict[key] = value
                        dict[currentSection] = sectionDict
                    }
                }
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            jsonOutput = string
        }
    }
}
