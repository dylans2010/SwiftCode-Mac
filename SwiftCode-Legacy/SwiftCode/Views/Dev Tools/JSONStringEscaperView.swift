import SwiftUI

public struct JSONStringEscaperView: View {
    @State private var inputText = ""
    @State private var outputText = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("JSON String Escaper & Unescaper")
                        .font(.title.bold())
                    Text("Convert raw multiline text blocks into escaped JSON string literal tokens cleanly.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Raw String Input")
                            .font(.headline)

                        TextEditor(text: $inputText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 140)
                            .padding(6)
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(6)

                        HStack {
                            Button("Escape String") {
                                performEscape()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)

                            Button("Unescape String") {
                                performUnescape()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)

                            Spacer()

                            Button("Clear All") {
                                inputText = ""
                                outputText = ""
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                if !outputText.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Output Result")
                                    .font(.headline)
                                Spacer()
                                Button("Copy Result") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(outputText, forType: .string)
                                }
                                .buttonStyle(.bordered)
                            }

                            Text(outputText)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func performEscape() {
        var result = inputText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        outputText = "\"\(result)\""
    }

    private func performUnescape() {
        var cleaned = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
            cleaned.removeFirst()
            cleaned.removeLast()
        }

        let result = cleaned
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")

        outputText = result
    }
}
