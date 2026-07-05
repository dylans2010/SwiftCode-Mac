import SwiftUI

struct DebuggingToolsView: View {
    @State private var runtimeLogs = ["App launched", "Indexer warm-up complete"]
    @State private var buildErrors = ["No build errors"]
    @State private var crashLogs = ["No crashes captured"]
    @State private var stackTrace = ["main", "ProjectWorkspaceView.body", "CodeEditorView.body"]
    @State private var memoryUsage = "128 MB"
    @State private var threadActivity = ["Main Thread: Idle", "Background Task #1: Indexing"]
    @State private var breakpoints = ["CodeEditorView.swift:142", "ProjectManager.swift:88"]
    @State private var consoleCommand = ""
    @State private var consoleOutput = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    panel("Runtime Log Viewer", systemImage: "text.append") { logList(runtimeLogs) }
                    panel("Build Error Inspector", systemImage: "exclamationmark.triangle") { logList(buildErrors) }
                    panel("Crash Log Analyzer", systemImage: "ant") { logList(crashLogs) }
                    panel("Stack Trace Viewer", systemImage: "list.number") { logList(stackTrace) }

                    HStack(spacing: 14) {
                        panel("Memory Usage", systemImage: "memorychip") {
                            Text(memoryUsage).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        panel("Thread Activity", systemImage: "cpu") { logList(threadActivity) }
                    }

                    panel("Breakpoint Manager", systemImage: "stop.circle") { logList(breakpoints) }

                    panel("Console Command Execution", systemImage: "terminal") {
                        HStack {
                            TextField("Enter console command", text: $consoleCommand)
                                .textFieldStyle(.roundedBorder)
                            Button("Run") {
                                consoleOutput.append("\n$ \(consoleCommand)\nExecuted")
                                consoleCommand = ""
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        ScrollView {
                            Text(consoleOutput.isEmpty ? "No console output." : consoleOutput)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 90)
                    }
                }
                .padding()
            }
            .navigationTitle("Debug Tools")
            .background(Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea())
        }
    }

    private func panel<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func logList(_ rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                Text(row)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
