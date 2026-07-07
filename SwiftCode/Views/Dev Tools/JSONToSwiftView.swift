import SwiftUI

struct JSONToSwiftView: View {
    @State private var jsonInput = ""
    @State private var swiftOutput = ""
    @State private var rootClassName = "Root"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Root Class Name:")
                    TextField("Root", text: $rootClassName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    Spacer()
                    Button("Generate Swift Models") {
                        generateSwift()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                HSplitView {
                    VStack(alignment: .leading) {
                        Text("JSON Input")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading)
                        TextEditor(text: $jsonInput)
                            .font(.system(.body, design: .monospaced))
                            .border(Color.secondary.opacity(0.2))
                    }
                    VStack(alignment: .leading) {
                        Text("Swift Output")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading)
                        TextEditor(text: .constant(swiftOutput))
                            .font(.system(.body, design: .monospaced))
                            .border(Color.secondary.opacity(0.2))
                    }
                }
            }
        }
        .navigationTitle("JSON to Swift Model")
    }

    func generateSwift() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            swiftOutput = "Invalid JSON input"
            return
        }

        swiftOutput = "import Foundation\n\n"
        swiftOutput += generateStruct(name: rootClassName, dict: json)
    }

    func generateStruct(name: String, dict: [String: Any]) -> String {
        var result = "struct \(name): Codable {\n"
        var nestedStructs = ""

        for (key, value) in dict {
            let swiftKey = key.replacingOccurrences(of: "-", with: "_")
            if let nestedDict = value as? [String: Any] {
                let nestedName = key.capitalized.replacingOccurrences(of: "_", with: "")
                result += "    let \(swiftKey): \(nestedName)\n"
                nestedStructs += "\n" + generateStruct(name: nestedName, dict: nestedDict)
            } else if let array = value as? [[String: Any]], let first = array.first {
                let nestedName = key.capitalized.replacingOccurrences(of: "_", with: "")
                result += "    let \(swiftKey): [\(nestedName)]\n"
                nestedStructs += "\n" + generateStruct(name: nestedName, dict: first)
            } else if value is String {
                result += "    let \(swiftKey): String\n"
            } else if value is Int {
                result += "    let \(swiftKey): Int\n"
            } else if value is Double {
                result += "    let \(swiftKey): Double\n"
            } else if value is Bool {
                result += "    let \(swiftKey): Bool\n"
            } else {
                result += "    let \(swiftKey): String? // Unknown type\n"
            }
        }

        result += "}\n"
        return result + nestedStructs
    }
}
