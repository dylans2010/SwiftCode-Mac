import SwiftUI

struct RegexTesterView: View {
    @State private var pattern = ""
    @State private var testString = ""
    @State private var results = ""

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading) {
                Text("Regular Expression Pattern")
                    .font(.headline)
                TextField("e.g. [a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: pattern) { test() }
            }

            VStack(alignment: .leading) {
                Text("Test String")
                    .font(.headline)
                TextEditor(text: $testString)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .onChange(of: testString) { test() }
            }

            VStack(alignment: .leading) {
                Text("Matches")
                    .font(.headline)
                ScrollView {
                    Text(results)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Regex Tester")
    }

    func test() {
        guard !pattern.isEmpty else {
            results = "Enter a pattern to test."
            return
        }

        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: testString, range: NSRange(testString.startIndex..., in: testString))

            if matches.isEmpty {
                results = "No matches found."
            } else {
                results = matches.enumerated().map { index, match in
                    let matchRange = Range(match.range, in: testString)!
                    return "Match \(index + 1): \"\(testString[matchRange])\" at range \(match.range)"
                }.joined(separator: "\n")
            }
        } catch {
            results = "Invalid Regex: \(error.localizedDescription)"
        }
    }
}
