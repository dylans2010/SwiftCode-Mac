import SwiftUI
import os.log

@Observable
@MainActor
final class AppStateInspectorViewModel {
    var stateLogs: [String] = []

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "AppStateInspector")

    func logStateChange(_ state: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        stateLogs.insert("[\(timestamp)] \(state)", at: 0)
        logger.info("Application State Event logged: \(state)")
    }
}

struct AppStateInspectorDevToolView: View {
    @State private var viewModel = AppStateInspectorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Inspect live changes to the application environment state and execution loops.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Simulate Active") {
                        viewModel.logStateChange("Active (Foreground)")
                    }
                    Button("Simulate Inactive") {
                        viewModel.logStateChange("Inactive (Transition)")
                    }
                    Button("Simulate Background") {
                        viewModel.logStateChange("Background")
                    }
                    Spacer()
                    Button("Clear History") {
                        viewModel.stateLogs.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(viewModel.stateLogs, id: \.self) { log in
                HStack {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.green)
                    Text(log)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .navigationTitle("App State Inspector")
        .onAppear {
            viewModel.logStateChange("App State Inspector initialized - active monitoring")
        }
    }
}
