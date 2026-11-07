import SwiftUI

struct JSONToPHPView: View {
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
                Button("Generate PHP") { generate() }
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
        .navigationTitle("JSON to PHP")
    }

    func generate() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            output = "Invalid JSON"
            return
        }
        output = "<?php\n\nclass \(className) {\n"
        for (key, _) in json {
            output += "    public $\(key);\n"
        }
        output += "}"
    }
}
