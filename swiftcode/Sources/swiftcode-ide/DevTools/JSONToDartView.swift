import SwiftUI

struct JSONToDartView: View {
    @State private var jsonInput = ""
    @State private var output = ""
    @State private var className = "Model"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Class Name:")
                TextField("Model", text: $className)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
                Button("Generate Dart") { generate() }
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
        .navigationTitle("JSON to Dart")
    }

    func generate() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            output = "Invalid JSON"
            return
        }
        output = "class \(className) {\n"
        for (key, value) in json {
            let type = getDartType(value)
            output += "  final \(type) \(key);\n"
        }
        output += "\n  \(className)({\n"
        for (key, _) in json {
            output += "    required this.\(key),\n"
        }
        output += "  });\n}"
    }

    func getDartType(_ value: Any) -> String {
        if value is String { return "String" }
        if value is Int { return "int" }
        if value is Double { return "double" }
        if value is Bool { return "bool" }
        return "dynamic"
    }
}
