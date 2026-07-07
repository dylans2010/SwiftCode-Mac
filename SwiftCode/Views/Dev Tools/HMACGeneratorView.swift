import SwiftUI
import CryptoKit

struct HMACGeneratorView: View {
    @State private var message = ""
    @State private var key = ""
    @State private var result = ""

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading) {
                Text("Message")
                    .font(.headline)
                TextEditor(text: $message)
                    .frame(height: 100)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            }

            VStack(alignment: .leading) {
                Text("Secret Key")
                    .font(.headline)
                TextField("your-secret-key", text: $key)
                    .textFieldStyle(.roundedBorder)
            }

            Button("Generate HMAC (SHA256)") { generate() }
                .buttonStyle(.borderedProminent)

            VStack(alignment: .leading) {
                Text("Result")
                    .font(.headline)
                Text(result)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("HMAC Generator")
    }

    func generate() {
        let keyData = SymmetricKey(data: Data(key.utf8))
        let messageData = Data(message.utf8)
        let signature = HMAC<SHA256>.authenticationCode(for: messageData, using: keyData)
        result = signature.map { String(format: "%02x", $0) }.joined()
    }
}
