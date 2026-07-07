import SwiftUI

struct WhoisLookupView: View {
    @State private var domain = "swift.org"
    @State private var results = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                TextField("domain.com", text: $domain)
                    .textFieldStyle(.roundedBorder)
                Button("Lookup") { lookup() }
                    .disabled(domain.isEmpty || isLoading)
            }
            .padding([.top, .horizontal])

            if isLoading {
                ProgressView()
            }

            ScrollView {
                Text(results)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)

            Spacer()
        }
        .navigationTitle("Whois Lookup")
    }

    func lookup() {
        isLoading = true
        // Mock Whois lookup
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isLoading = false
            results = """
            Domain Name: \(domain.uppercased())
            Registry Domain ID: 23456789_DOMAIN_ORG-VRSN
            Registrar WHOIS Server: whois.registrar.com
            Registrar URL: http://www.registrar.com
            Updated Date: 2023-01-15T10:00:00Z
            Creation Date: 2014-06-02T15:00:00Z
            Registry Expiry Date: 2025-06-02T15:00:00Z
            Registrar: Registrar Name, LLC
            """
        }
    }
}
