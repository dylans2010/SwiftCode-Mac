import SwiftUI

struct JSONToJavaView: View {
    @State private var jsonInput = ""
    @State private var output = ""
    @State private var className = "Response"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Class Name:")
                TextField("Response", text: $className)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
                Button("Generate Java") { generate() }
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
        .navigationTitle("JSON to Java")
    }

    func generate() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            output = "Invalid JSON"
            return
        }
        output = "public class \(className) {\n"
        for (key, value) in json {
            let type = getJavaType(value)
            output += "    private \(type) \(key);\n"
        }
        output += "}"
    }

    func getJavaType(_ value: Any) -> String {
        if value is String { return "String" }
        if value is Int { return "Integer" }
        if value is Double { return "Double" }
        if value is Bool { return "Boolean" }
        return "Object"
    }
}
