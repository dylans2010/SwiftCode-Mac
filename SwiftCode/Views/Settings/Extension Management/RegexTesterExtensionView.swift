import SwiftUI

// MARK: - Regex Tester Extension View
struct RegexTesterExtensionView: View {
    @State private var pattern = ""
    @State private var testInput = ""
    @State private var matches: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Pattern") {
                TextField(#"e.g. \d{3}-\d{4}"#, text: $pattern)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .onChange(of: pattern) { evaluate() }
                    .onChange(of: testInput) { evaluate() }
            }
            Section("Test Input") {
                TextEditor(text: $testInput)
                    .frame(minHeight: 80)
                    .font(.system(.body, design: .monospaced))
            }
            Section("Matches") {
                if let err = errorMessage {
                    Label(err, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                } else if matches.isEmpty {
                    Text(pattern.isEmpty ? "Enter a pattern above" : "No matches")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(Array(matches.enumerated()), id: \.offset) { i, m in
                        Text("[\(i + 1)] \(m)")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            Section {
                Text("Test regular expressions against sample input and see all matches highlighted. Supports ICU regex syntax.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Regex Tester")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func evaluate() {
        errorMessage = nil
        matches = []
        guard !pattern.isEmpty, !testInput.isEmpty else { return }
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(testInput.startIndex..., in: testInput)
            let found = regex.matches(in: testInput, range: range)
            matches = found.compactMap { result -> String? in
                guard let r = Range(result.range, in: testInput) else { return nil }
                return String(testInput[r])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
