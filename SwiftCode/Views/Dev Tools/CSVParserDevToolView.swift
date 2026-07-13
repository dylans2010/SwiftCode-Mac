import SwiftUI
import os.log

@Observable
@MainActor
final class CSVParserDevToolViewModel {
    var rawCSV: String = "Name,Role,Experience\nAlice,Developer,5 years\nBob,Architect,10 years\nCharlie,Designer,3 years"
    var headers: [String] = []
    var rows: [[String]] = []
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "CSVParser")

    func parse() {
        errorMessage = nil
        headers = []
        rows = []

        let lines = rawCSV.components(separatedBy: .newlines)
        let filteredLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        guard let firstLine = filteredLines.first else {
            errorMessage = "CSV input is empty."
            return
        }

        headers = firstLine.components(separatedBy: ",")

        for line in filteredLines.dropFirst() {
            let cols = line.components(separatedBy: ",")
            if cols.count == headers.count {
                rows.append(cols)
            } else {
                // Pad or truncate
                var adjusted = cols
                if adjusted.count < headers.count {
                    adjusted.append(contentsOf: Array(repeating: "", count: headers.count - adjusted.count))
                } else {
                    adjusted = Array(adjusted.prefix(headers.count))
                }
                rows.append(adjusted)
            }
        }
        logger.info("Successfully parsed CSV string containing \(self.rows.count) rows")
    }
}

struct CSVParserDevToolView: View {
    @State private var viewModel = CSVParserDevToolViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Parse CSV raw values and display them in a structured grid preview.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Comma-Separated Text (CSV)")
                        .font(.headline)
                    TextEditor(text: $viewModel.rawCSV)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))
                }

                Button("Parse CSV Grid") {
                    viewModel.parse()
                }
                .buttonStyle(.borderedProminent)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                }

                if !viewModel.headers.isEmpty {
                    Divider()

                    Text("Structured Output Preview")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 0) {
                        // Headers
                        HStack {
                            ForEach(viewModel.headers, id: \.self) { header in
                                Text(header)
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.15))
                            }
                        }

                        // Rows
                        ForEach(0..<viewModel.rows.count, id: \.self) { rowIndex in
                            HStack {
                                ForEach(0..<viewModel.rows[rowIndex].count, id: \.self) { colIndex in
                                    Text(viewModel.rows[rowIndex][colIndex])
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .border(Color.secondary.opacity(0.1), width: 0.5)
                                }
                            }
                        }
                    }
                    .border(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                }
            }
            .padding()
        }
        .navigationTitle("CSV Parser")
        .onAppear {
            viewModel.parse()
        }
    }
}
