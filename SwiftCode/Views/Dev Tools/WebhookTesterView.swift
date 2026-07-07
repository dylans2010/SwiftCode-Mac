import SwiftUI

struct WebhookTesterView: View {
    @State private var webhookURL = ""
    @State private var payload = "{\n  \"message\": \"Hello from SwiftCode!\"\n}"
    @State private var resultMessage = ""
    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Test your incoming webhooks by sending a sample payload.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading) {
                Text("Webhook URL")
                    .font(.caption)
                TextField("https://hooks.slack.com/services/...", text: $webhookURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading) {
                Text("JSON Payload")
                    .font(.caption)
                TextEditor(text: $payload)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 200)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            HStack {
                Button("Send Webhook") {
                    sendWebhook()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || webhookURL.isEmpty)

                if isSending {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                Spacer()

                Text(resultMessage)
                    .foregroundColor(resultMessage.contains("Success") ? .green : .red)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Webhook Tester")
    }

    func sendWebhook() {
        guard let url = URL(string: webhookURL) else {
            resultMessage = "Invalid URL"
            return
        }

        isSending = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isSending = false
                if let error = error {
                    resultMessage = "Error: \(error.localizedDescription)"
                } else if let httpResponse = response as? HTTPURLResponse {
                    if (200...299).contains(httpResponse.statusCode) {
                        resultMessage = "Success! Status: \(httpResponse.statusCode)"
                    } else {
                        resultMessage = "Failed. Status: \(httpResponse.statusCode)"
                    }
                }
            }
        }.resume()
    }
}
