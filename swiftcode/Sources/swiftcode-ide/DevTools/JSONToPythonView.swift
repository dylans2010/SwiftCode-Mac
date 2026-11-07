import SwiftUI

struct JSONToPythonView: View {
    @State private var jsonInput = ""
    @State private var output = ""
    @State private var className = "Data"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Class Name:")
                TextField("Data", text: $className)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
                Button("Generate Python") { generate() }
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
        .navigationTitle("JSON to Python")
    }

    func generate() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            output = "Invalid JSON"
            return
        }
        output = "from dataclasses import dataclass\n\n@dataclass\nclass \(className):\n"
        for (key, value) in json {
            let type = getPythonType(value)
            output += "    \(key): \(type)\n"
        }
    }

    func getPythonType(_ value: Any) -> String {
        if value is String { return "str" }
        if value is Int { return "int" }
        if value is Double { return "float" }
        if value is Bool { return "bool" }
        return "Any"
    }
}
