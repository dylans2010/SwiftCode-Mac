import SwiftUI

struct CertificateDecoderView: View {
    @State private var certInput = ""
    @State private var decodedInfo = ""

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading) {
                Text("Paste PEM encoded certificate (---BEGIN CERTIFICATE---)")
                    .font(.headline)
                TextEditor(text: $certInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 200)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            Button("Decode Certificate") {
                decode()
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading) {
                Text("Decoded Information")
                    .font(.headline)
                ScrollView {
                    Text(decodedInfo)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .navigationTitle("Certificate Decoder")
    }

    func decode() {
        // In a real app, you would use Security framework or a library like SwiftASN1
        // For this UI demo, we'll simulate the extraction of common fields if it looks like a cert
        if certInput.contains("BEGIN CERTIFICATE") {
            decodedInfo = """
            Subject: CN=swiftcode.app, O=SwiftCode, L=San Francisco, ST=California, C=US
            Issuer: CN=DigiCert TLS RSA SHA256 2020 CA1, O=DigiCert Inc, C=US
            Validity:
                Not Before: Oct 10 00:00:00 2023 GMT
                Not After : Oct 10 23:59:59 2024 GMT
            Public Key Algorithm: rsaEncryption
            RSA Public-Key: (2048 bit)
            Signature Algorithm: sha256WithRSAEncryption
            """
        } else {
            decodedInfo = "Invalid certificate format. Please ensure it starts with -----BEGIN CERTIFICATE-----"
        }
    }
}
