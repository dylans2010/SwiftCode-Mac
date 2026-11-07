import SwiftUI

struct JSONToTSView: View {
    @State private var jsonInput = ""
    @State private var output = ""
    @State private var interfaceName = "Root"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Interface Name:")
                TextField("Root", text: $interfaceName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
                Button("Generate TS") { generate() }
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
        .navigationTitle("JSON to TypeScript")
    }

    func generate() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            output = "Invalid JSON"
            return
        }
        output = "interface \(interfaceName) {\n"
        for (key, value) in json {
            let type = getTSType(value)
            output += "    \(key): \(type);\n"
        }
        output += "}"
    }

    func getTSType(_ value: Any) -> String {
        if value is String { return "string" }
        if value is Int || value is Double { return "number" }
        if value is Bool { return "boolean" }
        if value is [String: Any] { return "object" }
        if value is [Any] { return "any[]" }
        return "any"
    }
}
