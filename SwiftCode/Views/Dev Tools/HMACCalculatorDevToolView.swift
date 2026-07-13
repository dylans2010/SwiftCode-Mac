import SwiftUI
import CryptoKit
import os.log

@Observable
@MainActor
final class HMACCalculatorViewModel {
    var rawInput: String = "Hello SwiftCode!"
    var secretKey: String = "MySecretHMACKey!!"
    var outputDigest: String = ""

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "HMACCalculator")

    func computeHMAC() {
        let key = SymmetricKey(data: Data(secretKey.utf8))
        let data = Data(rawInput.utf8)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        outputDigest = signature.map { String(format: "%02x", $0) }.joined()
        logger.info("Successfully computed HMAC SHA-256 code")
    }
}

struct HMACCalculatorDevToolView: View {
    @State private var viewModel = HMACCalculatorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Compute secure HMAC SHA-256 message authentication codes using shared keys.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("UTF-8 Raw Text Input")
                        .font(.headline)
                    TextEditor(text: $viewModel.rawInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .border(Color.secondary.opacity(0.2))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Shared Secret Key")
                        .font(.headline)
                    TextField("Enter key", text: $viewModel.secretKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Button("Compute HMAC") {
                    viewModel.computeHMAC()
                }
                .buttonStyle(.borderedProminent)

                if !viewModel.outputDigest.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Resulting HMAC Signature")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(viewModel.outputDigest, forType: .string)
                            }) {
                                Label("Copy Signature", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }

                        TextEditor(text: .constant(viewModel.outputDigest))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 80)
                            .border(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("HMAC Calculator")
        .onAppear {
            viewModel.computeHMAC()
        }
    }
}
