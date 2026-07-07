import SwiftUI

struct YAMLConverterView: View {
    @State private var jsonInput = "{\n  \"name\": \"John Doe\",\n  \"age\": 30,\n  \"city\": \"New York\"\n}"
    @State private var yamlOutput = ""

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("JSON Input")
                        .font(.caption)
                    TextEditor(text: $jsonInput)
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading) {
                    Text("YAML Output")
                        .font(.caption)
                    TextEditor(text: .constant(yamlOutput))
                        .font(.system(.body, design: .monospaced))
                }
            }

            Button("Convert JSON to YAML") { convert() }
                .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .navigationTitle("YAML Converter")
    }

    func convert() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            yamlOutput = "Invalid JSON"
            return
        }

        yamlOutput = jsonToYaml(json, indent: 0)
    }

    func jsonToYaml(_ dict: [String: Any], indent: Int) -> String {
        var result = ""
        let prefix = String(repeating: "  ", count: indent)
        for (key, value) in dict {
            if let nested = value as? [String: Any] {
                result += "\(prefix)\(key):\n" + jsonToYaml(nested, indent: indent + 1)
            } else if let array = value as? [Any] {
                result += "\(prefix)\(key):\n"
                for item in array {
                    result += "\(prefix)  - \(item)\n"
                }
            } else {
                result += "\(prefix)\(key): \(value)\n"
            }
        }
        return result
    }
}
