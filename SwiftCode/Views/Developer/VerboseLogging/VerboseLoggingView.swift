import SwiftUI

struct VerboseLoggingView: View {
    @StateObject private var logger = InternalLoggingManager.shared
    @StateObject private var flags = FeatureFlags.shared

    var body: some View {
        VStack {
            Form {
                Section {
                    Toggle("Enable Verbose Logging", isOn: $flags.verbose_logging)
                }

                Section {
                    Button("Clear Logs") {
                        logger.clearLogs()
                    }
                    Button("Export Logs") {
                        let text = logger.exportLogs()
                        print(text)
                    }
                }
            }

            List(logger.logs) { log in
                VStack(alignment: .leading) {
                    HStack {
                        Text(log.category.rawValue)
                            .font(.caption.bold())
                            .padding(.horizontal, 4)
                            .background(Color.blue.opacity(0.2))
                        Spacer()
                        Text(log.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(log.message)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .navigationTitle("Verbose Logging")
    }
}
