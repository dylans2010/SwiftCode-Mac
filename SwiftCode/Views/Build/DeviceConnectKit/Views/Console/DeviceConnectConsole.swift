import SwiftUI

public struct DeviceConnectConsole: View {
    @State private var consoleManager = ConsoleManager.shared
    @State private var searchText = ""
    @State private var filterSeverity: DeviceLog.Severity? = nil

    public init() {}

    private var filteredLogs: [DeviceLog] {
        let logs = consoleManager.selectedConsoleTab == 0 ? consoleManager.buildLogs : consoleManager.runtimeLogs
        return logs.filter { log in
            (searchText.isEmpty || log.message.localizedCaseInsensitiveContains(searchText)) &&
            (filterSeverity == nil || log.severity == filterSeverity)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header bar / selectors
            HStack {
                Picker("Console Output", selection: $consoleManager.selectedConsoleTab) {
                    Text("Build Compiler").tag(0)
                    Text("Device System Logs").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Spacer()

                // Severity Filter
                Picker("Severity", selection: $filterSeverity) {
                    Text("All").tag(nil as DeviceLog.Severity?)
                    Text("Info").tag(DeviceLog.Severity.info as DeviceLog.Severity?)
                    Text("Warnings").tag(DeviceLog.Severity.warning as DeviceLog.Severity?)
                    Text("Errors").tag(DeviceLog.Severity.error as DeviceLog.Severity?)
                }
                .frame(width: 150)

                // Clear button
                Button(action: { consoleManager.clearLogs() }) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Log output list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLogs) { log in
                            HStack(alignment: .top, spacing: 6) {
                                Text("[\(formattedTime(log.timestamp))]")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                if !log.category.isEmpty {
                                    Text("[\(log.category)]")
                                        .font(.system(.caption, design: .monospaced).weight(.bold))
                                        .foregroundStyle(.blue)
                                }

                                Text(log.message)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(logColor(log.severity))
                            }
                            .id(log.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: filteredLogs.count) { _, _ in
                    if let last = filteredLogs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func logColor(_ severity: DeviceLog.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .debug: return .secondary
        case .info: return .primary
        }
    }
}
