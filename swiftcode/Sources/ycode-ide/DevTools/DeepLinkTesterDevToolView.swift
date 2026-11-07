import SwiftUI
import YcodeUI
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

        #if canImport(AppKit)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            logs.insert("[\(timestamp)] Failed: No application is registered to open scheme “\(url.scheme ?? "")”.", at: 0)
            logger.info("Deep link not opened: no application registered for scheme \(url.scheme ?? "")")
            return
        }
        if NSWorkspace.shared.open(url) {
            logs.insert("[\(timestamp)] Opened: \(url.absoluteString) (handler: \(appURL.lastPathComponent))", at: 0)
            logger.info("Successfully opened deep link: \(self.rawURL)")
        } else {
            logs.insert("[\(timestamp)] Failed: The system refused to open \(url.absoluteString).", at: 0)
            logger.info("Deep link open refused by the system: \(self.rawURL)")
        }
        #else
        logs.insert("Failed: Opening URLs needs NSWorkspace (AppKit), which is unavailable on this platform.", at: 0)
        #endif
    }
}

struct DeepLinkTesterDevToolView: View {
    @State private var viewModel = DeepLinkTesterViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Test deep link schemes by opening the URL with the application the system has registered for it, and see the real result.")
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
            .liquidGlass(style: .subtle, cornerRadius: 12)
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
