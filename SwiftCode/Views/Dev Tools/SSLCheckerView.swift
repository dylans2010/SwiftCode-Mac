import SwiftUI

struct SSLCheckerView: View {
    @State private var domain = "apple.com"
    @State private var report = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                TextField("domain.com", text: $domain)
                    .textFieldStyle(.roundedBorder)
                Button("Check SSL") { check() }
                    .disabled(domain.isEmpty || isLoading)
            }
            .padding([.top, .horizontal])

            if isLoading {
                ProgressView()
            }

            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)

            Spacer()
        }
        .navigationTitle("SSL Checker")
    }

    func check() {
        isLoading = true
        // Mock SSL check
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isLoading = false
            report = """
            Checking \(domain)...

            [Summary]
            Status: VALID
            Expires: in 245 days

            [Certificate Details]
            Common Name: \(domain)
            Issuer: DigiCert Inc
            Algorithm: sha256WithRSAEncryption
            Key Strength: 2048 bits

            [Protocol Support]
            TLS 1.3: Yes
            TLS 1.2: Yes
            TLS 1.1: No (Secure)
            """
        }
    }
}
