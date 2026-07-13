import SwiftUI
import os.log

@Observable
@MainActor
final class DeepLinkTesterViewModel {
    var rawURL: String = "swiftcode://open?project=demo&file=main.swift"
    var logs: [String] = []

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "DeepLinkTester")

    func triggerDeepLink() {
        guard let url = URL(string: rawURL) else {
            logs.insert("Failed: Invalid URL structure: \(rawURL)", at: 0)
            return
        }

        // Simulates deep link URL route dispatching inside active window
        let timestamp = ISO8601DateFormatter().string(from: Date())
        logs.insert("[\(timestamp)] Dispatched: \(url.absoluteString)", at: 0)
        logger.info("Successfully dispatched deep link simulation: \(self.rawURL)")
    }
}

struct DeepLinkTesterDevToolView: View {
    @State private var viewModel = DeepLinkTesterViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Test deep link schemes and simulated application URL routing integrations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TextField("swiftcode://...", text: $viewModel.rawURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button("Trigger URL Link") {
                        viewModel.triggerDeepLink()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(viewModel.logs, id: \.self) { log in
                HStack {
                    Image(systemName: "link.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)

                    Text(log)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .navigationTitle("Deep Link Tester")
    }
}
