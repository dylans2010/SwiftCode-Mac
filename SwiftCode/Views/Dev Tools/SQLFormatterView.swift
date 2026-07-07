import SwiftUI

struct SQLFormatterView: View {
    @State private var input = "SELECT * FROM users WHERE id = 1 AND status = 'active' ORDER BY created_at DESC"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button("Format SQL") { format() }
                    .buttonStyle(.borderedProminent)
            }
            .padding([.top, .horizontal])

            VStack(alignment: .leading) {
                Text("Input")
                    .font(.headline)
                TextEditor(text: $input)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Output")
                    .font(.headline)
                TextEditor(text: .constant(output))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding([.bottom, .horizontal])
        }
        .navigationTitle("SQL Formatter")
        .onAppear { format() }
    }

    func format() {
        // Simple mock SQL formatter
        var formatted = input
        let keywords = ["SELECT", "FROM", "WHERE", "AND", "OR", "ORDER BY", "GROUP BY", "LIMIT", "INSERT INTO", "UPDATE", "DELETE", "JOIN", "LEFT JOIN", "RIGHT JOIN"]

        for keyword in keywords {
            formatted = formatted.replacingOccurrences(of: keyword, with: "\n\(keyword)", options: .caseInsensitive)
        }

        output = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
