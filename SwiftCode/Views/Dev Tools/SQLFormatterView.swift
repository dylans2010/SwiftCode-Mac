import SwiftUI

struct SQLFormatterView: View {
    @State private var sqlInput = "SELECT * FROM users WHERE id = 1 AND status = 'active' ORDER BY created_at DESC"
    @State private var sqlOutput = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Format SQL") { format() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()

            HSplitView {
                TextEditor(text: $sqlInput)
                    .font(.system(.body, design: .monospaced))
                TextEditor(text: .constant(sqlOutput))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("SQL Formatter")
    }

    func format() {
        let keywords = ["SELECT", "FROM", "WHERE", "AND", "OR", "GROUP BY", "ORDER BY", "LIMIT", "INSERT INTO", "UPDATE", "DELETE", "JOIN", "LEFT JOIN", "RIGHT JOIN"]
        var formatted = sqlInput

        for keyword in keywords {
            formatted = formatted.replacingOccurrences(of: keyword, with: "\n" + keyword, options: .caseInsensitive)
        }

        sqlOutput = formatted.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
