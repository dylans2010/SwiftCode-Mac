import SwiftUI
import Security

struct RSAKeyGeneratorView: View {
    @State private var keySize = 2048
    @State private var publicKey = ""
    @State private var privateKey = ""
    @State private var isGenerating = false

    var body: some View {
        VStack(spacing: 20) {
            Picker("Key Size", selection: $keySize) {
                Text("1024 bits").tag(1024)
                Text("2048 bits").tag(2048)
                Text("4096 bits").tag(4096)
            }
            .pickerStyle(.segmented)
            .padding()

            Button(isGenerating ? "Generating..." : "Generate Key Pair") { generate() }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)

            HSplitView {
                VStack(alignment: .leading) {
                    Text("Public Key (DER Base64)")
                    TextEditor(text: .constant(publicKey))
                        .font(.system(.caption, design: .monospaced))
                }
                VStack(alignment: .leading) {
                    Text("Private Key (In Keychain)")
                    TextEditor(text: .constant(privateKey))
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .padding()

            Spacer()
        }
        .navigationTitle("RSA Key Generator")
    }

    func generate() {
        isGenerating = true
        DispatchQueue.global(qos: .userInitiated).async {
            let parameters: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits as String: keySize,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String: false
                ]
            ]

            var error: Unmanaged<CFError>?
            guard let privKey = SecKeyCreateRandomKey(parameters as CFDictionary, &error) else {
                DispatchQueue.main.async {
                    self.privateKey = "Error: \(error!.takeRetainedValue() as Error)"
                    self.isGenerating = false
                }
                return
            }

            let pubKey = SecKeyCopyPublicKey(privKey)!
            let pubData = SecKeyCopyExternalRepresentation(pubKey, &error)! as Data

            DispatchQueue.main.async {
                self.publicKey = pubData.base64EncodedString(options: .lineLength64Characters)
                self.privateKey = "Private key generated and held in memory/keychain."
                self.isGenerating = false
            }
        }
    }
}
