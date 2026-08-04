import SwiftUI

struct SCLogsView: View {
    @State private var lc = LoggingCenter.shared
    @State private var filterText = ""

    let logTypes = ["Build", "Virtualization", "Cloud", "Signing", "Diagnostics"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logging Center")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Inspect real-time telemetry from active builds, hypervisors, and security modules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Copy and export actions
                HStack(spacing: 8) {
                    Button {
                        copyToClipboard()
                    } label: {
                        Label("Copy Logs", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        exportLogs()
                    } label: {
                        Label("Export...", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)

            Divider()

            // Segments selection and filtering
            HStack {
                Picker("Log Stream", selection: Binding(
                    get: { lc.activeLogType },
                    set: { lc.setLogType($0) }
                )) {
                    ForEach(logTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 450)

                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter stream...", text: $filterText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
                .frame(width: 250)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Console output area
            let filteredLogs = lc.logs.filter {
                filterText.isEmpty || $0.lowercased().contains(filterText.lowercased())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if filteredLogs.isEmpty {
                        Text("No log messages matching filter query.")
                            .italic()
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredLogs, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(colorForLogLine(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.underPageBackgroundColor))
        }
        .onAppear {
            lc.loadLogs()
        }
    }

    private func colorForLogLine(_ line: String) -> Color {
        let l = line.lowercased()
        if l.contains("[error]") || l.contains("error:") || l.contains("[critical]") {
            return .red
        } else if l.contains("[warning]") || l.contains("warning:") {
            return .yellow
        } else if l.contains("[system]") || l.contains("[info]") {
            return .green
        }
        return .primary
    }

    private func copyToClipboard() {
        let allText = lc.logs.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(allText, forType: .string)
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = "\(lc.activeLogType)_log.txt"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let allText = lc.logs.joined(separator: "\n")
                try? allText.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
