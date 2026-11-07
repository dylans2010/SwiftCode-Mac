import SwiftUI

struct JSONToCSharpView: View {
    @State private var jsonInput = ""
    @State private var output = ""
    @State private var className = "Root"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Class Name:")
                TextField("Root", text: $className)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
                Button("Generate C#") { generate() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $jsonInput)
                    .font(.system(.body, design: .monospaced))
                TextEditor(text: .constant(output))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("JSON to C#")
    }

    func generate() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            output = "Invalid JSON"
            return
        }
        output = "public class \(className)\n{\n"
        for (key, value) in json {
            let type = getCSharpType(value)
            let fieldName = key.prefix(1).uppercased() + key.dropFirst()
            output += "    public \(type) \(fieldName) { get; set; }\n"
        }
        output += "}"
    }

    func getCSharpType(_ value: Any) -> String {
        if value is String { return "string" }
        if value is Int { return "int" }
        if value is Double { return "double" }
        if value is Bool { return "bool" }
        return "object"
    }
}
