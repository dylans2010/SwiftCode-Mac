import SwiftUI

struct IPAddressInfoView: View {
    @State private var ipAddress = ""
    @State private var info = "Enter an IP address to get location info."
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                TextField("8.8.8.8", text: $ipAddress)
                    .textFieldStyle(.roundedBorder)

                Button("Get Info") { getInfo() }
                    .disabled(ipAddress.isEmpty || isLoading)
            }
            .padding([.top, .horizontal])

            if isLoading {
                ProgressView()
            }

            VStack(alignment: .leading) {
                Text("IP Details")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    Text(info)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding([.bottom, .horizontal])

            Spacer()
        }
        .navigationTitle("IP Address Info")
    }

    func getInfo() {
        guard let url = URL(string: "https://ipapi.co/\(ipAddress)/json/") else { return }
        isLoading = true

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    info = "Error: \(error.localizedDescription)"
                    return
                }
                if let data = data, let result = String(data: data, encoding: .utf8) {
                    info = result
                }
            }
        }.resume()
    }
}
