import SwiftUI
import Security

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
        let cleanPem = certInput.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
                                .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
                                .replacingOccurrences(of: "\n", with: "")
                                .replacingOccurrences(of: "\r", with: "")

        guard let data = Data(base64Encoded: cleanPem) else {
            decodedInfo = "Invalid Base64 data in certificate."
            return
        }

        if let cert = SecCertificateCreateWithData(nil, data as CFData) {
            if let summary = SecCertificateCopySubjectSummary(cert) {
                decodedInfo = "Subject: \(summary as String)\n"
            }

            // For more details we would need SecCertificateCopyValues, but it's complex to parse.
            // We'll provide at least the summary and basic confirmation.
            decodedInfo += "\nCertificate successfully parsed by Security framework."
        } else {
            decodedInfo = "Could not parse certificate data using Security framework."
        }
    }
}
