import SwiftUI

struct AnalyzedKey: Identifiable {
    let id = UUID()
    let path: String
    let typeName: String
    let valueSummary: String
}

public struct JSONTypeAnalyzerView: View {
    @State private var jsonInput = "{\n  \"id\": 101,\n  \"title\": \"SwiftCode Developer IDE\",\n  \"isActive\": true,\n  \"metrics\": {\n    \"viewsCount\": 1420,\n    \"rating\": 4.95\n  },\n  \"categories\": [\"Productivity\", \"Swift\", \"macOS\"]\n}"
    @State private var analyzedKeys: [AnalyzedKey] = []
    @State private var errorMessage: String? = nil

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("JSON Type Analyzer")
                        .font(.title.bold())
                    Text("Parse and analyze a JSON payload to recursively list all keys, nested object paths, and concrete values.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Raw Input JSON Payload")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        TextEditor(text: $jsonInput)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 140)
                            .padding(6)
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(6)

                        Button("Analyze Structural Types") {
                            analyzeJSON()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                if let err = errorMessage {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.subheadline.bold())
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(6)
                }

                if !analyzedKeys.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Analyzed Key-Value Properties Schema")
                                .font(.headline)

                            // Headers
                            HStack {
                                Text("Key Path")
                                    .font(.caption.bold())
                                    .frame(width: 220, alignment: .leading)
                                Text("Schema Type")
                                    .font(.caption.bold())
                                    .frame(width: 120, alignment: .leading)
                                Text("Value Preview")
                                    .font(.caption.bold())
                                Spacer()
                            }
                            .foregroundColor(.secondary)

                            Divider()

                            ForEach(analyzedKeys) { item in
                                HStack {
                                    Text(item.path)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .frame(width: 220, alignment: .leading)
                                        .foregroundColor(.orange)

                                    Text(item.typeName)
                                        .font(.caption.bold())
                                        .frame(width: 120, alignment: .leading)
                                        .foregroundColor(.blue)

                                    Text(item.valueSummary)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)

                                    Spacer()
                                }
                                .padding(.vertical, 3)
                            }
                        }
                        .padding(10)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func analyzeJSON() {
        errorMessage = nil
        analyzedKeys = []

        guard let data = jsonInput.data(using: .utf8) else {
            errorMessage = "Error: Input is not a valid UTF-8 string payload."
            return
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            var tempKeys: [AnalyzedKey] = []
            parseRecursive(json: json, currentPath: "", results: &tempKeys)
            analyzedKeys = tempKeys
        } catch {
            errorMessage = "Serialization Error: \(error.localizedDescription)"
        }
    }

    private func parseRecursive(json: Any, currentPath: String, results: inout [AnalyzedKey]) {
        if let dict = json as? [String: Any] {
            for (key, val) in dict {
                let nextPath = currentPath.isEmpty ? key : "\(currentPath).\(key)"
                parseRecursive(json: val, currentPath: nextPath, results: &results)
            }
        } else if let arr = json as? [Any] {
            let itemPath = "\(currentPath)[]"
            results.append(AnalyzedKey(path: itemPath, typeName: "Array (\(arr.count) items)", valueSummary: "[\(arr.prefix(3).map { String(describing: $0) }.joined(separator: ", "))]"))
            if let first = arr.first {
                parseRecursive(json: first, currentPath: "\(currentPath)[0]", results: &results)
            }
        } else {
            let typeStr: String
            if json is String {
                typeStr = "String"
            } else if json is Bool {
                typeStr = "Boolean"
            } else if let num = json as? NSNumber {
                typeStr = CFNumberGetTypeID() == CFGetTypeID(num) ? "Double" : "Integer"
            } else {
                typeStr = "Null / Variant"
            }
            results.append(AnalyzedKey(path: currentPath, typeName: typeStr, valueSummary: String(describing: json)))
        }
    }
}
