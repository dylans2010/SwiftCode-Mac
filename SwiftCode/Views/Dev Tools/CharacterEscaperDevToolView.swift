import SwiftUI
import os.log

@Observable
@MainActor
final class CharacterEscaperViewModel {
    var rawText: String = "Hello \"World\"\nThis is a \\ backslash."
    var escapedText: String = ""

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "CharacterEscaper")

    func escape() {
        var escaped = ""
        for scalar in rawText.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(Character(scalar))
            }
        }
        escapedText = escaped
        logger.info("Successfully escaped text string")
    }

    func unescape() {
        // Simple unescape conversion
        var result = escapedText
        result = result.replacingOccurrences(of: "\\\"", with: "\"")
        result = result.replacingOccurrences(of: "\\\\", with: "\\")
        result = result.replacingOccurrences(of: "\\n", with: "\n")
        result = result.replacingOccurrences(of: "\\r", with: "\r")
        result = result.replacingOccurrences(of: "\\t", with: "\t")
        rawText = result
        logger.info("Successfully unescaped text string")
    }
}

struct CharacterEscaperDevToolView: View {
    @State private var viewModel = CharacterEscaperViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Escape or unescape double quotes, backslashes, and control characters for code literals.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw Plaintext Input")
                        .font(.headline)
                    TextEditor(text: $viewModel.rawText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))

                    Button("Escape Characters") {
                        viewModel.escape()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Escaped Code Literal")
                        .font(.headline)
                    TextEditor(text: $viewModel.escapedText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))

                    Button("Unescape Characters") {
                        viewModel.unescape()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Character Escaper")
        .onAppear {
            viewModel.escape()
        }
    }
}
