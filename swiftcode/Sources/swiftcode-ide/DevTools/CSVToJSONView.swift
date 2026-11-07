import SwiftUI

struct CSVToJSONView: View {
    @State private var csvInput = "id,name,email\n1,John Doe,john@example.com\n2,Jane Smith,jane@example.com"
    @State private var jsonOutput = ""
    @State private var delimiter = ","

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Delimiter:")
                TextField(",", text: $delimiter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 40)
                Spacer()
                Button("Convert to JSON") { convert() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $csvInput)
                    .font(.system(.body, design: .monospaced))
                TextEditor(text: .constant(jsonOutput))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("CSV to JSON")
    }

    func convert() {
        let lines = csvInput.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else {
            jsonOutput = "Invalid CSV: Need at least a header and one row."
            return
        }

        let headers = lines[0].components(separatedBy: delimiter)
        var result: [[String: String]] = []

        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: delimiter)
            var dict: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                if index < values.count {
                    dict[header.trimmingCharacters(in: .whitespaces)] = values[index].trimmingCharacters(in: .whitespaces)
                }
            }
            result.append(dict)
        }

        if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            jsonOutput = string
        } else {
            jsonOutput = "Conversion failed."
        }
    }
}
