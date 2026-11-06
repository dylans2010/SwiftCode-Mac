// Ported from SwiftCode-Legacy `SwiftCode/Views/Dev Tools/NetworkReachabilityDevToolView.swift` (Dylan's own code; direct port authorised under MIT).
// V10 (independent verification): confirmed genuinely missing from production at bc28f653.
// Verbatim port: no references to Legacy-only types; `import SwiftCodeUI` added for .liquidGlass.
import SwiftUI
import SwiftCodeUI
import os.log

@Observable
@MainActor
final class NetworkReachabilityViewModel {
    var isConnected: Bool = true
    var connectionType: String = "Wi-Fi (En0)"
    var logs: [String] = []

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "NetworkReachability")

    func checkReachability() {
        isConnected = true
        connectionType = "Wi-Fi (En0) - Active"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        logs.insert("[\(timestamp)] Interface en0 status: Up (Reachable)", at: 0)
        logger.info("Checked system network reachability: Connected via \(self.connectionType)")
    }
}

struct NetworkReachabilityDevToolView: View {
    @State private var viewModel = NetworkReachabilityViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Monitor real-time network interface connection states and active routing paths.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: viewModel.isConnected ? "wifi" : "wifi.slash")
                        .foregroundColor(viewModel.isConnected ? .green : .red)
                        .font(.title)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.isConnected ? "Internet Connection Active" : "No Connection Detected")
                            .font(.headline)
                        Text(viewModel.connectionType)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Refresh Link") {
                        viewModel.checkReachability()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .liquidGlass(style: .subtle, cornerRadius: 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(viewModel.logs, id: \.self) { log in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(log)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .navigationTitle("Network Reachability Monitor")
        .onAppear {
            viewModel.checkReachability()
        }
    }
}
