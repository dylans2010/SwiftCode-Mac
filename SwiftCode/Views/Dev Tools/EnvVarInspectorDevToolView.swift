import SwiftUI
import os.log

@Observable
@MainActor
final class EnvVarInspectorViewModel {
    var rawVars: [String: String] = [:]
    var filterText: String = ""

    var filteredVars: [(String, String)] {
        let sorted = rawVars.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
        if filterText.isEmpty {
            return sorted
        } else {
            return sorted.filter {
                $0.0.lowercased().contains(filterText.lowercased()) ||
                $0.1.lowercased().contains(filterText.lowercased())
            }
        }
    }

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "EnvVarInspector")

    func loadEnv() {
        rawVars = ProcessInfo.processInfo.environment
        logger.info("Successfully scanned and fetched \(self.rawVars.count) active environment variables.")
    }
}

struct EnvVarInspectorDevToolView: View {
    @State private var viewModel = EnvVarInspectorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Search and inspect active environment variables defined on the workspace parent process.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Filter by key or value...", text: $viewModel.filterText)
                        .textFieldStyle(.roundedBorder)

                    Button("Scan Environment") {
                        viewModel.loadEnv()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(viewModel.filteredVars, id: \.0) { key, value in
                VStack(alignment: .leading, spacing: 4) {
                    Text(key)
                        .font(.headline)
                        .foregroundColor(.blue)

                    Text(value)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Environment Variable Inspector")
        .onAppear {
            viewModel.loadEnv()
        }
    }
}
