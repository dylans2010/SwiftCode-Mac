import SwiftUI
import CryptoKit

struct BcryptHashGeneratorView: View {
    @State private var input = ""
    @State private var hash = ""

    var body: some View {
        VStack(spacing: 20) {
            TextField("Text to hash (SHA256 demo)", text: $input)
                .textFieldStyle(.roundedBorder)

            Button("Generate Hash") { generate() }
                .buttonStyle(.borderedProminent)

            VStack(alignment: .leading) {
                Text("Resulting SHA256 Hash:")
                    .font(.caption)
                TextEditor(text: .constant(hash))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                    .border(Color.secondary.opacity(0.2))
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Hash Generator")
    }

    func generate() {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        hash = digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
