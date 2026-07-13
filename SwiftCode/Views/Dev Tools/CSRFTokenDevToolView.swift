import SwiftUI
import CryptoKit
import os.log

@Observable
@MainActor
final class CSRFTokenDevToolViewModel {
    var generatedToken: String = ""
    var strengthBits: Int = 256

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "CSRFToken")

    func generateToken() {
        let bytesCount = strengthBits / 8
        var bytes = [UInt8](repeating: 0, count: bytesCount)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytesCount, &bytes)

        if result == errSecSuccess {
            generatedToken = Data(bytes).map { String(format: "%02x", $0) }.joined()
            logger.info("Successfully generated secure CSRF anti-forgery token.")
        } else {
            // Fallback securely in case SecRandom fails
            let randomData = (0..<bytesCount).map { _ in UInt8.random(in: 0...255) }
            generatedToken = Data(randomData).map { String(format: "%02x", $0) }.joined()
        }
    }
}

struct CSRFTokenDevToolView: View {
    @State private var viewModel = CSRFTokenDevToolViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Generate cryptographically secure anti-forgery tokens (CSRF) for HTTP session security headers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Entropy Size (bits)", selection: $viewModel.strengthBits) {
                    Text("128 bits").tag(128)
                    Text("256 bits").tag(256)
                    Text("512 bits").tag(512)
                }
                .pickerStyle(.segmented)

                Button("Generate Secure Token") {
                    viewModel.generateToken()
                }
                .buttonStyle(.borderedProminent)

                if !viewModel.generatedToken.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Secure Hex Token")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(viewModel.generatedToken, forType: .string)
                            }) {
                                Label("Copy Token", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }

                        TextEditor(text: .constant(viewModel.generatedToken))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 100)
                            .border(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("CSRF Token Generator")
        .onAppear {
            viewModel.generateToken()
        }
    }
}
