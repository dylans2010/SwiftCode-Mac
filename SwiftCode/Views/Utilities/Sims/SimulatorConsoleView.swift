import SwiftUI

struct SimulatorConsoleView: View {
    @State private var manager = SimulatorManager.shared
    @State private var searchText = ""
    @State private var autoScroll = true

    var filteredLogs: [String] {
        if searchText.isEmpty {
            return manager.consoleLogs
        }
        return manager.consoleLogs.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Console Output", systemImage: "terminal.fill")
                        .font(.headline)
                        .foregroundColor(.green)

                    Spacer()

                    TextField("Search Logs...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    Toggle("Auto Scroll", isOn: $autoScroll)
                        .toggleStyle(.checkbox)

                    Button("Clear") {
                        manager.clearConsoleLogs()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Export") {
                        exportLogsToFile()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if filteredLogs.isEmpty {
                                Text("Console buffer empty. Ready to capture simulator outputs.")
                                    .foregroundColor(.secondary)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                            } else {
                                ForEach(filteredLogs.indices, id: \.self) { idx in
                                    Text(filteredLogs[idx])
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(filteredLogs[idx].contains("FAILED") ? .red : .primary)
                                        .textSelection(.enabled)
                                        .id(idx)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(8)
                    .frame(height: 180)
                    .onChange(of: filteredLogs.count) { _, count in
                        if autoScroll && count > 0 {
                            withAnimation {
                                proxy.scrollTo(count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func exportLogsToFile() {
        let text = manager.consoleLogs.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "SimulatorLogs.txt"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
