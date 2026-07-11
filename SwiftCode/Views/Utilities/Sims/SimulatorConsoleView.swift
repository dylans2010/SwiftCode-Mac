import AppKit
import SwiftUI

/// Professional monospaced text output stream for system processes and boot diagnostics.
public struct SimulatorConsoleView: View {
    @Environment(SimulatorManager.self) private var simulatorManager
    @State private var searchQuery = ""

    public var body: some View {
        VStack(spacing: 0) {
            // Console Toolbar
            HStack {
                Label("Simulator Diagnostics & Activity Console", systemImage: "terminal")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                // Search Box
                TextField("Search Logs...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .autocorrectionDisabled()

                // Buttons Group
                HStack(spacing: 6) {
                    Button(action: copyToClipboard) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .help("Copy logs to Clipboard")

                    Button(action: exportToFile) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .help("Export logs to external text file")

                    Button(action: {
                        Task {
                            await simulatorManager.clearLogs()
                        }
                    }) {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Clear Console logs")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Logs stream list
            let filteredLogs = simulatorManager.consoleLogs.filter {
                searchQuery.isEmpty || $0.message.localizedCaseInsensitiveContains(searchQuery) || $0.level.localizedCaseInsensitiveContains(searchQuery)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if filteredLogs.isEmpty {
                            Text("No activity logged.")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            ForEach(filteredLogs) { entry in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(formatDate(entry.timestamp))
                                        .foregroundStyle(.secondary)

                                    Text("[\(entry.level)]")
                                        .foregroundStyle(colorForLevel(entry.level))
                                        .fontWeight(.semibold)

                                    Text(entry.message)
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                }
                                .font(.system(.caption, design: .monospaced))
                                .tag(entry.id)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(red: 0.08, green: 0.08, blue: 0.10))
                .onChange(of: filteredLogs.count) { _, _ in
                    if let last = filteredLogs.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    private func colorForLevel(_ level: String) -> Color {
        switch level.uppercased() {
        case "ERROR": return .red
        case "WARNING": return .yellow
        case "SUCCESS": return .green
        default: return .blue
        }
    }

    private func copyToClipboard() {
        let text = simulatorManager.consoleLogs.map { "[\($0.level)] \($0.message)" }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func exportToFile() {
        let text = simulatorManager.consoleLogs.map { "[\($0.level)] \($0.message)" }.joined(separator: "\n")
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text]
        savePanel.nameFieldStringValue = "simulator_diagnostics.log"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
