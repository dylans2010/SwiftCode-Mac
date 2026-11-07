import SwiftUI

struct JSONToTOMLView: View {
    @State private var jsonInput = "{\n  \"title\": \"Example\",\n  \"owner\": {\"name\": \"Tom\", \"age\": 30}\n}"
    @State private var tomlOutput = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Convert JSON to TOML") { convert() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $jsonInput)
                    .font(.system(.body, design: .monospaced))
                TextEditor(text: .constant(tomlOutput))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("JSON to TOML")
    }

    func convert() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tomlOutput = "Invalid JSON"
            return
        }

        var result = ""
        for (key, value) in json {
            if let nested = value as? [String: Any] {
                result += "[\(key)]\n"
                for (nk, nv) in nested {
                    result += "\(nk) = \"\(nv)\"\n"
                }
                result += "\n"
            } else {
                result += "\(key) = \"\(value)\"\n"
            }
        }
        tomlOutput = result
    }
}
