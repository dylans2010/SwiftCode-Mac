import SwiftUI
import os.log

@Observable
@MainActor
final class Base64EncoderViewModel {
    var rawInput: String = "Hello SwiftCode Developer!"
    var encodedOutput: String = ""

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "Base64Encoder")

    func encode() {
        let data = Data(rawInput.utf8)
        encodedOutput = data.base64EncodedString()
        logger.info("Successfully encoded input text to Base64")
    }
}

struct Base64EncoderDevToolView: View {
    @State private var viewModel = Base64EncoderViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Encode plain text strings into standard base64 formats.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Plaintext")
                        .font(.headline)
                    TextEditor(text: $viewModel.rawInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))
                }

                Button("Encode Base64") {
                    viewModel.encode()
                }
                .buttonStyle(.borderedProminent)

                if !viewModel.encodedOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Base64 Encoded Output")
                            .font(.headline)
                            .foregroundColor(.blue)

                        TextEditor(text: .constant(viewModel.encodedOutput))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 150)
                            .border(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Base64 Encoder")
    }
}
