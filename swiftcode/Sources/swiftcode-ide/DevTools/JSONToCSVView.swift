import SwiftUI

struct JSONToCSVView: View {
    @State private var jsonInput = "[\n  {\"id\": 1, \"name\": \"John\"},\n  {\"id\": 2, \"name\": \"Jane\"}\n]"
    @State private var csvOutput = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Convert to CSV") { convert() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $jsonInput)
                    .font(.system(.body, design: .monospaced))
                TextEditor(text: .constant(csvOutput))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("JSON to CSV")
    }

    func convert() {
        guard let data = jsonInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = json.first else {
            csvOutput = "Invalid JSON: Expecting an array of objects."
            return
        }

        let headers = first.keys.sorted()
        var csv = headers.joined(separator: ",") + "\n"

        for item in json {
            let row = headers.map { "\(item[$0] ?? "")" }.joined(separator: ",")
            csv += row + "\n"
        }
        csvOutput = csv
    }
}
