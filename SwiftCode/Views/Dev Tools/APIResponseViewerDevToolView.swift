import SwiftUI
import os.log

@Observable
@MainActor
final class APIResponseViewerDevToolViewModel {
    var urlString: String = "https://api.github.com"
    var isFetching: Bool = false
    var responseHeaders: String = ""
    var responseBody: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "APIResponseViewer")

    func fetchAPI() async {
        guard let url = URL(string: urlString), url.scheme != nil else {
            errorMessage = "Invalid URL address."
            return
        }

        isFetching = true
        errorMessage = nil
        responseBody = ""
        responseHeaders = ""

        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let headers = httpResponse.allHeaderFields.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                responseHeaders = "Status Code: \(httpResponse.statusCode)\n\n\(headers)"
            }

            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let formattedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
               let prettyString = String(data: formattedData, encoding: .utf8) {
                responseBody = prettyString
            } else {
                responseBody = String(data: data, encoding: .utf8) ?? "No raw string readable."
            }

            logger.info("Successfully fetched API response from \(self.urlString)")
        } catch {
            errorMessage = "Request failed: \(error.localizedDescription)"
            logger.error("API response fetch failed: \(error.localizedDescription)")
        }

        isFetching = false
    }
}

struct APIResponseViewerDevToolView: View {
    @State private var viewModel = APIResponseViewerDevToolViewModel()
    @State private var selectedPane = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("View and pretty-print JSON API responses from any HTTP target URL.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TextField("Enter HTTP API URL", text: $viewModel.urlString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button(action: {
                        Task { await viewModel.fetchAPI() }
                    }) {
                        if viewModel.isFetching {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Send GET")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isFetching)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption.bold())
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            Picker("", selection: $selectedPane) {
                Text("JSON Body").tag(0)
                Text("HTTP Response Headers").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedPane == 0 {
                TextEditor(text: .constant(viewModel.responseBody))
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal)
            } else {
                TextEditor(text: .constant(viewModel.responseHeaders))
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal)
            }

            Spacer().frame(height: 16)
        }
        .navigationTitle("API Response Viewer")
    }
}
