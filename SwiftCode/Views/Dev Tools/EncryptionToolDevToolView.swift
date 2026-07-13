import SwiftUI
import CryptoKit
import os.log

@Observable
@MainActor
final class EncryptionToolViewModel {
    var rawInput: String = "Hello SwiftCode!"
    var algorithm: String = "SHA256"
    var outputHash: String = ""

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "EncryptionTool")

    func compute() {
        let data = Data(rawInput.utf8)

        switch algorithm {
        case "SHA1":
            let digest = Insecure.SHA1.hash(data: data)
            outputHash = digest.map { String(format: "%02x", $0) }.joined()
        case "SHA256":
            let digest = SHA256.hash(data: data)
            outputHash = digest.map { String(format: "%02x", $0) }.joined()
        case "SHA512":
            let digest = SHA512.hash(data: data)
            outputHash = digest.map { String(format: "%02x", $0) }.joined()
        default:
            outputHash = ""
        }

        logger.info("Successfully executed block cipher hashing for algorithm: \(self.algorithm)")
    }
}

struct EncryptionToolDevToolView: View {
    @State private var viewModel = EncryptionToolViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Compute cryptographically secure data digests using multi-algorithm hashing hashes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("UTF-8 Raw Text Input")
                        .font(.headline)
                    TextEditor(text: $viewModel.rawInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))
                }

                Picker("Hash Algorithm", selection: $viewModel.algorithm) {
                    Text("SHA-1").tag("SHA1")
                    Text("SHA-256").tag("SHA256")
                    Text("SHA-512").tag("SHA512")
                }
                .pickerStyle(.radioGroup)

                Button("Generate Hash Digest") {
                    viewModel.compute()
                }
                .buttonStyle(.borderedProminent)

                if !viewModel.outputHash.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Output Digest Hex String")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(viewModel.outputHash, forType: .string)
                            }) {
                                Label("Copy Hash", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }

                        TextEditor(text: .constant(viewModel.outputHash))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 100)
                            .border(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Encryption Hash Tool")
        .onAppear {
            viewModel.compute()
        }
    }
}
