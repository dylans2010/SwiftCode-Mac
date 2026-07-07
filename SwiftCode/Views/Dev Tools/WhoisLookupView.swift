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
        // Using a public WHOIS API
        guard let url = URL(string: "https://rdap.org/domain/\(domain)") else {
            isLoading = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    results = "Error: \(error.localizedDescription)"
                    return
                }
                if let data = data, let result = String(data: data, encoding: .utf8) {
                    results = result
                }
            }
        }.resume()
    }
}
