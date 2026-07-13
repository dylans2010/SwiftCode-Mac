import SwiftUI
import CryptoKit
import os.log

@Observable
@MainActor
final class AESEncryptionDevToolViewModel {
    var plainText: String = ""
    var keyString: String = "My32ByteSecretKeyForEncryption!!" // 32 bytes
    var cipherText: String = ""
    var decryptedText: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "AESEncryption")

    func encrypt() {
        errorMessage = nil
        guard let keyData = keyString.data(using: .utf8), keyData.count == 32 else {
            errorMessage = "Encryption key must be exactly 32 bytes (characters) long."
            return
        }

        let key = SymmetricKey(data: keyData)
        guard let plainTextData = plainText.data(using: .utf8) else {
            errorMessage = "Invalid plaintext string encoding."
            return
        }

        do {
            let sealedBox = try AES.GCM.seal(plainTextData, using: key)
            cipherText = sealedBox.combined?.base64EncodedString() ?? ""
            logger.info("Successfully encrypted plain text using AES-256 GCM")
        } catch {
            errorMessage = "Encryption error: \(error.localizedDescription)"
            logger.error("Encryption failed: \(error.localizedDescription)")
        }
    }

    func decrypt() {
        errorMessage = nil
        guard let keyData = keyString.data(using: .utf8), keyData.count == 32 else {
            errorMessage = "Decryption key must be exactly 32 bytes (characters) long."
            return
        }

        let key = SymmetricKey(data: keyData)
        guard let cipherData = Data(base64Encoded: cipherText) else {
            errorMessage = "Ciphertext is not a valid Base64 string."
            return
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: cipherData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            decryptedText = String(data: decryptedData, encoding: .utf8) ?? ""
            logger.info("Successfully decrypted cipher text using AES-256 GCM")
        } catch {
            errorMessage = "Decryption error: \(error.localizedDescription)"
            logger.error("Decryption failed: \(error.localizedDescription)")
        }
    }
}

struct AESEncryptionDevToolView: View {
    @State private var viewModel = AESEncryptionDevToolViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Encrypt and decrypt text strings using secure AES-256 GCM algorithm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Secret Key (exactly 32 characters)")
                        .font(.headline)
                    TextField("Enter 32-character key", text: $viewModel.keyString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Divider()

                // Encryption Part
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plaintext Input")
                        .font(.headline)
                    TextEditor(text: $viewModel.plainText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .border(Color.secondary.opacity(0.2))

                    Button("Encrypt plaintext") {
                        viewModel.encrypt()
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Decryption Part
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ciphertext (Base64 combined format)")
                        .font(.headline)
                    TextEditor(text: $viewModel.cipherText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .border(Color.secondary.opacity(0.2))

                    HStack {
                        Button("Decrypt ciphertext") {
                            viewModel.decrypt()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(viewModel.cipherText, forType: .string)
                        }) {
                            Label("Copy Ciphertext", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.cipherText.isEmpty)
                    }
                }

                if !viewModel.decryptedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Decrypted Output")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text(viewModel.decryptedText)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption.bold())
                }
            }
            .padding()
        }
        .navigationTitle("AES Encryption Tool")
    }
}
