import SwiftUI

struct APITesterView: View {
    @State private var url = "https://api.github.com"
    @State private var method = "GET"
    @State private var responseText = ""
    @State private var isLoading = false

    let methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Picker("Method", selection: $method) {
                    ForEach(methods, id: \.self) { method in
                        Text(method)
                    }
                }
                .frame(width: 100)

                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)

                Button("Send") {
                    sendRequest()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isLoading)
            }
            .padding([.top, .horizontal])

            if isLoading {
                ProgressView()
                    .padding()
            }

            TextEditor(text: .constant(responseText))
                .font(.system(.body, design: .monospaced))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding([.bottom, .horizontal])
        }
        .navigationTitle("API Tester")
    }

    func sendRequest() {
        guard let requestUrl = URL(string: url) else {
            responseText = "Invalid URL"
            return
        }

        isLoading = true
        var request = URLRequest(url: requestUrl)
        request.httpMethod = method

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    responseText = "Error: \(error.localizedDescription)"
                    return
                }

                if let data = data {
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []),
                       let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        responseText = prettyString
                    } else {
                        responseText = String(data: data, encoding: .utf8) ?? "Unable to parse response"
                    }
                }
            }
        }.resume()
    }
}
