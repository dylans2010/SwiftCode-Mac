// Ported from SwiftCode-Legacy (Dylan's own code, MIT-authorised direct port).
// Rebuilt in Ycode style: default accent, no Legacy liquid-glass/orange styling.

#if canImport(CryptoKit)
import SwiftUI
import CryptoKit

struct BcryptHashGeneratorView: View {
    @State private var input = ""
    @State private var hash = ""

    var body: some View {
        VStack(spacing: 20) {
            TextField("Text to hash (SHA-256)", text: $input)
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
        
        .navigationTitle("SHA-256 Hash Generator")
    }

    func generate() {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        hash = digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#else
struct BcryptHashGeneratorView: View {
    var body: some View {
        DevToolsUnavailableView(reason: "Hashing needs CryptoKit, which is unavailable on this platform.")
    }
}
#endif
