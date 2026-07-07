import SwiftUI

struct DNSLookupView: View {
    @State private var domain = "google.com"
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

            VStack(alignment: .leading) {
                Text("DNS Records")
                    .font(.headline)
                ScrollView {
                    Text(results)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding([.bottom, .horizontal])

            Spacer()
        }
        .navigationTitle("DNS Lookup")
    }

    func lookup() {
        isLoading = true
        // Mock DNS lookup
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isLoading = false
            results = """
            ; <<>> DiG 9.10.6 <<>> \(domain) ANY
            ;; ANSWER SECTION:
            \(domain).    300 IN  A   142.250.190.46
            \(domain).    3600    IN  NS  ns1.google.com.
            \(domain).    3600    IN  MX  10 aspmx.l.google.com.
            """
        }
    }
}
