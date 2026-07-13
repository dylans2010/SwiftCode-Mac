import SwiftUI
import os.log

@Observable
@MainActor
final class CURLGeneratorDevToolViewModel {
    var urlString: String = "https://api.github.com/users/dylans2010"
    var httpMethod: String = "GET"
    var authorizationHeader: String = "Bearer my_secret_token"
    var generatedCURL: String = ""

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "CURLGenerator")

    func generate() {
        var cmd = "curl -X \(httpMethod) \"\(urlString)\""
        if !authorizationHeader.isEmpty {
            cmd += " -H \"Authorization: \(authorizationHeader)\""
        }
        cmd += " -H \"Accept: application/json\""

        generatedCURL = cmd
        logger.info("Successfully generated cURL string from parameters.")
    }
}

struct CURLGeneratorDevToolView: View {
    @State private var viewModel = CURLGeneratorDevToolViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Generate standard cURL console commands from visual URLRequest parameters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Target URL")
                        .font(.headline)
                    TextField("Enter target", text: $viewModel.urlString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                HStack(spacing: 20) {
                    Picker("Method", selection: $viewModel.httpMethod) {
                        Text("GET").tag("GET")
                        Text("POST").tag("POST")
                        Text("PUT").tag("PUT")
                        Text("DELETE").tag("DELETE")
                    }
                    .frame(width: 150)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Authorization Header")
                            .font(.caption)
                        TextField("Bearer tokens...", text: $viewModel.authorizationHeader)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Button("Generate cURL") {
                    viewModel.generate()
                }
                .buttonStyle(.borderedProminent)

                if !viewModel.generatedCURL.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Command Line cURL output")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(viewModel.generatedCURL, forType: .string)
                            }) {
                                Label("Copy Command", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }

                        TextEditor(text: .constant(viewModel.generatedCURL))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 100)
                            .border(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("cURL Generator")
        .onAppear {
            viewModel.generate()
        }
    }
}
