import SwiftUI
import os.log

@Observable
@MainActor
final class AppReceiptInspectorViewModel {
    var rawReceiptBase64: String = "MIAGCSqGSIb3DQEHAqCAMIACAQExDzANBglghkgBZQMEAgEFADCABgkqhkiG9w0BBwGggCSABIIBNDELMAkGA1UEBhMCVVMxEzARBgNVBAoTCkFwcGxlIEluYy4xLDAqBgNVBAsTI0FwcGxlIFdvcmxkd2lkZSBEZXZlbG9wZXIgQ29uZ2Vzc2lvbjE="
    var parsedPayload: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "AppReceiptInspector")

    func parseReceipt() {
        errorMessage = nil
        parsedPayload = ""

        guard !rawReceiptBase64.isEmpty else {
            errorMessage = "Please provide receipt file base64 data."
            return
        }

        // Simulates PKCS7 ASN.1 decoding payload structure for App Store receipts
        if Data(base64Encoded: rawReceiptBase64) != nil {
            parsedPayload = """
            {
              "bundle_id": "com.swiftcode.app",
              "application_version": "1.0.0",
              "original_application_version": "1.0.0",
              "creation_date": "\(Date().description)",
              "in_app_purchases": [
                {
                  "quantity": "1",
                  "product_id": "com.swiftcode.pro_yearly",
                  "transaction_id": "1000000921827431",
                  "original_transaction_id": "1000000921827431",
                  "purchase_date": "2026-03-12 14:22:10 UTC",
                  "expires_date": "2027-03-12 14:22:10 UTC"
                }
              ]
            }
            """
            logger.info("Successfully decoded app receipt mock")
        } else {
            errorMessage = "Receipt data is not a valid Base64 encoded payload."
        }
    }
}

struct AppReceiptInspectorDevToolView: View {
    @State private var viewModel = AppReceiptInspectorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Analyze and inspect App Store receipt payloads (PKCS#7 containers) to verify purchase models.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste Raw App Receipt (Base64 string)")
                        .font(.headline)
                    TextEditor(text: $viewModel.rawReceiptBase64)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))
                }

                Button("Decode App Receipt") {
                    viewModel.parseReceipt()
                }
                .buttonStyle(.borderedProminent)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption.bold())
                }

                if !viewModel.parsedPayload.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Decoded Receipt Attributes")
                            .font(.headline)
                            .foregroundColor(.blue)

                        TextEditor(text: .constant(viewModel.parsedPayload))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 200)
                            .border(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("App Receipt Inspector")
    }
}
