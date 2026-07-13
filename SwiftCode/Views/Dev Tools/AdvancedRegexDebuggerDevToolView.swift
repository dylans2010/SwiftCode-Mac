import SwiftUI
import os.log

@Observable
@MainActor
final class AdvancedRegexDebuggerViewModel {
    var regexPattern: String = "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b" // Email pattern
    var sampleText: String = "Send requests to support@example.com or info@swiftcode.dev for info."
    var matchResults: [String] = []
    var explanation: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "AdvancedRegexDebugger")

    func testRegex() {
        errorMessage = nil
        matchResults = []
        explanation = ""

        guard !regexPattern.isEmpty else {
            errorMessage = "Please enter a regular expression pattern."
            return
        }

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [])
            let range = NSRange(sampleText.startIndex..<sampleText.endIndex, in: sampleText)
            let matches = regex.matches(in: sampleText, options: [], range: range)

            for match in matches {
                if let subRange = Range(match.range, in: sampleText) {
                    matchResults.append(String(sampleText[subRange]))
                }
            }

            // Build simple structural explanation
            explanation = "Parsed Pattern: '\(regexPattern)'\nDetected \(matches.count) matched substring(s) in the sample text."
            logger.info("Successfully executed regex query")
        } catch {
            errorMessage = "Regex compilation failed: \(error.localizedDescription)"
            logger.error("Regex error: \(error.localizedDescription)")
        }
    }
}

struct AdvancedRegexDebuggerDevToolView: View {
    @State private var viewModel = AdvancedRegexDebuggerViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Debug, test, and analyze regular expressions interactively against sample text data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Regex Pattern")
                        .font(.headline)
                    TextField("Enter pattern", text: $viewModel.regexPattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample Text")
                        .font(.headline)
                    TextEditor(text: $viewModel.sampleText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .border(Color.secondary.opacity(0.2))
                }

                Button("Evaluate Regex") {
                    viewModel.testRegex()
                }
                .buttonStyle(.borderedProminent)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption.bold())
                }

                if !viewModel.explanation.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Analysis Summary")
                            .font(.headline)
                        Text(viewModel.explanation)
                            .font(.subheadline)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Matches (\(viewModel.matchResults.count))")
                        .font(.headline)

                    if viewModel.matchResults.isEmpty {
                        Text("No matching strings found.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(viewModel.matchResults, id: \.self) { match in
                            Text(match)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Advanced Regex Debugger")
    }
}
