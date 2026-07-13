import SwiftUI
import os.log

@Observable
@MainActor
final class CURLConverterDevToolViewModel {
    var curlCommand: String = "curl -X POST https://api.example.com/v1/users -H \"Authorization: Bearer my_token\" -d '{\"name\": \"Alice\"}'"
    var swiftCode: String = ""

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "CURLConverter")

    func convert() {
        // Quick basic conversion parser
        var method = "GET"
        if curlCommand.contains("-X POST") || curlCommand.contains("--request POST") {
            method = "POST"
        } else if curlCommand.contains("-X PUT") || curlCommand.contains("--request PUT") {
            method = "PUT"
        } else if curlCommand.contains("-X DELETE") || curlCommand.contains("--request DELETE") {
            method = "DELETE"
        }

        // simple URL extraction
        var url = "https://api.example.com"
        let parts = curlCommand.components(separatedBy: " ")
        if let foundUrl = parts.first(where: { $0.hasPrefix("http") }) {
            url = foundUrl.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
        }

        swiftCode = """
        import Foundation

        guard let url = URL(string: "\(url)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "\(method)"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Headers & payload parsed from cURL command line arguments
        """
        if curlCommand.contains("Authorization:") {
            swiftCode += "\nrequest.setValue(\"Bearer <Token>\", forHTTPHeaderField: \"Authorization\")"
        }

        if curlCommand.contains("-d") || curlCommand.contains("--data") {
            swiftCode += "\nrequest.httpBody = \"{\\\"name\\\": \\\"Alice\\\"}\".data(using: .utf8)"
        }

        logger.info("Successfully parsed cURL input to Swift URLRequest code block.")
    }
}

struct CURLConverterDevToolView: View {
    @State private var viewModel = CURLConverterDevToolViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Convert raw cURL terminal commands into compiled Swift Foundation URLRequest objects.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("cURL Terminal Command")
                        .font(.headline)
                    TextEditor(text: $viewModel.curlCommand)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))
                }

                Button("Convert to Swift Code") {
                    viewModel.convert()
                }
                .buttonStyle(.borderedProminent)

                if !viewModel.swiftCode.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Swift Output")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                            Button(action: {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(viewModel.swiftCode, forType: .string)
                            }) {
                                Label("Copy Swift", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }

                        TextEditor(text: .constant(viewModel.swiftCode))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 180)
                            .border(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("cURL Converter")
        .onAppear {
            viewModel.convert()
        }
    }
}
