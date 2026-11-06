// Ported from SwiftCode-Legacy (Dylan's own code, MIT-authorised direct port).
// Rebuilt in SwiftCode style: default accent, no Legacy liquid-glass/orange styling.

#if canImport(CryptoKit)
import SwiftUI
import CryptoKit

struct HashGeneratorView: View {
    @State private var inputText = ""
    @State private var md5Hash = ""
    @State private var sha1Hash = ""
    @State private var sha256Hash = ""
    @State private var sha512Hash = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Input Text")
                        .font(.headline)
                    TextEditor(text: $inputText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .onChange(of: inputText) { generateHashes() }
                }

                HashResultRow(label: "MD5", hash: md5Hash)
                HashResultRow(label: "SHA-1", hash: sha1Hash)
                HashResultRow(label: "SHA-256", hash: sha256Hash)
                HashResultRow(label: "SHA-512", hash: sha512Hash)
            }
            .padding()
        }
        
        .navigationTitle("Hash Generator")
    }

    func generateHashes() {
        let data = Data(inputText.utf8)

        // MD5 and SHA-1 come from CryptoKit's Insecure namespace; all four digests below are real.

        sha256Hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        sha512Hash = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        sha1Hash = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        md5Hash = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct HashResultRow: View {
    let label: String
    let hash: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hash, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            Text(hash.isEmpty ? "..." : hash)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
    }
}

#else
struct HashGeneratorView: View {
    var body: some View {
        DevToolsUnavailableView(reason: "Hashing needs CryptoKit, which is unavailable on this platform.")
    }
}
#endif
