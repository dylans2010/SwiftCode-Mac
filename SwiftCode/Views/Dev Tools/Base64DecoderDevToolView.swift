import SwiftUI
import os.log

@Observable
@MainActor
final class Base64DecoderViewModel {
    var base64Input: String = "SGVsbG8gU3dpZnRDb2RlIERldmVsb3BlciE="
    var decodedOutput: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "Base64Decoder")

    func decode() {
        errorMessage = nil
        decodedOutput = ""

        guard let data = Data(base64Encoded: base64Input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Invalid Base64 format."
            return
        }

        if let decodedString = String(data: data, encoding: .utf8) {
            decodedOutput = decodedString
            logger.info("Successfully decoded Base64 text")
        } else {
            errorMessage = "Decoded binary payload is not valid UTF-8 text."
        }
    }
}

struct Base64DecoderDevToolView: View {
    @State private var viewModel = Base64DecoderViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Decode standard base64 encoded strings into human readable text.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Base64 Encoded Text")
                        .font(.headline)
                    TextEditor(text: $viewModel.base64Input)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))
                }

                Button("Decode Base64") {
                    viewModel.decode()
                }
                .buttonStyle(.borderedProminent)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption.bold())
                }

                if !viewModel.decodedOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Decoded Text")
                            .font(.headline)
                            .foregroundColor(.green)

                        TextEditor(text: .constant(viewModel.decodedOutput))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 150)
                            .border(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Base64 Decoder")
    }
}
