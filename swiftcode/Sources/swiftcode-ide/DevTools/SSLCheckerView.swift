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
        guard let url = URL(string: "https://api.ssllabs.com/api/v3/analyze?host=\(domain)") else {
            isLoading = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    report = "Error: \(error.localizedDescription)"
                    return
                }
                if let data = data, let result = String(data: data, encoding: .utf8) {
                    report = result
                }
            }
        }.resume()
    }
}
