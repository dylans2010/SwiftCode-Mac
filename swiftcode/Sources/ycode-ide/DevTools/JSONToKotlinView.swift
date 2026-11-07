import SwiftUI

struct JSONToKotlinView: View {
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
                Button("Generate Kotlin") { generate() }
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
        .navigationTitle("JSON to Kotlin")
    }

    func generate() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            output = "Invalid JSON"
            return
        }
        output = "data class \(className)(\n"
        for (key, value) in json {
            let type = getKotlinType(value)
            output += "    val \(key): \(type),\n"
        }
        output += ")"
    }

    func getKotlinType(_ value: Any) -> String {
        if value is String { return "String" }
        if value is Int { return "Int" }
        if value is Double { return "Double" }
        if value is Bool { return "Boolean" }
        if value is [String: Any] { return "Any" }
        if value is [Any] { return "List<Any>" }
        return "Any?"
    }
}
