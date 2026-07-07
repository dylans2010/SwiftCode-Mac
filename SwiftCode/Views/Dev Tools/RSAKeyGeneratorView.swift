import SwiftUI

struct RSAKeyGeneratorView: View {
    @State private var keySize = 2048
    @State private var publicKey = ""
    @State private var privateKey = ""
    @State private var isGenerating = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Picker("Key Size", selection: $keySize) {
                    Text("1024").tag(1024)
                    Text("2048").tag(2048)
                    Text("4096").tag(4096)
                }
                .frame(width: 200)

                Button("Generate Keys") { generate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
            }
            .padding(.top)

            if isGenerating {
                ProgressView("Generating keys...")
            }

            HStack(spacing: 20) {
                KeyBox(label: "Public Key", key: publicKey)
                KeyBox(label: "Private Key", key: privateKey)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("RSA Key Generator")
    }

    func generate() {
        isGenerating = true
        // Mock key generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isGenerating = false
            publicKey = "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA7V...\n-----END PUBLIC KEY-----"
            privateKey = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA7Vv...\n-----END RSA PRIVATE KEY-----"
        }
    }
}

struct KeyBox: View {
    let label: String
    let key: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.headline)
            TextEditor(text: .constant(key))
                .font(.system(.caption, design: .monospaced))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
    }
}
