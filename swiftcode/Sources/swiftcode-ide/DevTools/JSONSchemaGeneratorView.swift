import SwiftUI

struct JSONSchemaGeneratorView: View {
    @State private var jsonInput = "{\n  \"id\": 1,\n  \"name\": \"A green door\",\n  \"price\": 12.50,\n  \"tags\": [\"home\", \"green\"]\n}"
    @State private var schemaOutput = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Generate JSON Schema") { generate() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $jsonInput)
                    .font(.system(.body, design: .monospaced))
                TextEditor(text: .constant(schemaOutput))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("JSON Schema Generator")
    }

    func generate() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            schemaOutput = "Invalid JSON"
            return
        }

        var schema: [String: Any] = [
            "$schema": "http://json-schema.org/draft-07/schema#",
            "type": "object",
            "properties": [String: Any]()
        ]

        var properties = [String: Any]()
        for (key, value) in json {
            properties[key] = ["type": getJsonSchemaType(value)]
        }
        schema["properties"] = properties

        if let schemaData = try? JSONSerialization.data(withJSONObject: schema, options: .prettyPrinted),
           let string = String(data: schemaData, encoding: .utf8) {
            schemaOutput = string
        }
    }

    func getJsonSchemaType(_ value: Any) -> String {
        if value is String { return "string" }
        if value is Int { return "integer" }
        if value is Double { return "number" }
        if value is Bool { return "boolean" }
        if value is [Any] { return "array" }
        if value is [String: Any] { return "object" }
        return "null"
    }
}
