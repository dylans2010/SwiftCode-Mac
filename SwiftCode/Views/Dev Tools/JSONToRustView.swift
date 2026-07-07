import SwiftUI

struct JSONToRustView: View {
    @State private var jsonInput = ""
    @State private var output = ""
    @State private var structName = "Response"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Struct Name:")
                TextField("Response", text: $structName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
                Button("Generate Rust") { generate() }
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
        .navigationTitle("JSON to Rust")
    }

    func generate() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            output = "Invalid JSON"
            return
        }
        output = "#[derive(Serialize, Deserialize)]\nstruct \(structName) {\n"
        for (key, value) in json {
            let type = getRustType(value)
            output += "    pub \(key): \(type),\n"
        }
        output += "}"
    }

    func getRustType(_ value: Any) -> String {
        if value is String { return "String" }
        if value is Int { return "i64" }
        if value is Double { return "f64" }
        if value is Bool { return "bool" }
        return "Value"
    }
}
