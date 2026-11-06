import SwiftUI

public struct TestToolsView: View {
    let project: Project
    @StateObject private var testManager = TestToolsManager.shared
    @State private var searchConsoleQuery = ""
    @State private var autoScrollConsole = true

    public init(project: Project) {
        self.project = project
    }

    private var filteredConsoleOutput: String {
        if searchConsoleQuery.isEmpty {
            return testManager.consoleOutput
        }
        let lines = testManager.consoleOutput.split(separator: "\n")
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(searchConsoleQuery) }
        return filtered.joined(separator: "\n")
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Card 1: Test Metrics Summary
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Testing Metrics", systemImage: "chart.bar.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            HStack(spacing: 24) {
                                // Status
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("STATUS")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 6) {
                                        if testManager.isRunning {
                                            ProgressView().scaleEffect(0.6)
                                            Text("Running").font(.body.bold()).foregroundStyle(.blue)
                                        } else {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundStyle(.green)
                                            Text("Ready").font(.body.bold()).foregroundStyle(.green)
                                        }
                                    }
                                }
                                .frame(width: 120, alignment: .leading)

                                Divider().frame(height: 30)

                                // Passed
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("PASSED")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    Text("\(testManager.passedCount)")
                                        .font(.title2.bold())
                                        .foregroundStyle(.green)
                                }
                                .frame(width: 80, alignment: .leading)

                                Divider().frame(height: 30)

                                // Failed
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("FAILED")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    Text("\(testManager.failedCount)")
                                        .font(.title2.bold())
                                        .foregroundStyle(testManager.failedCount > 0 ? .red : .primary)
                                }
                                .frame(width: 80, alignment: .leading)

                                Divider().frame(height: 30)

                                // Duration
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("DURATION")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "%.1f s", testManager.duration))
                                        .font(.title2.bold())
                                }
                                .frame(width: 100, alignment: .leading)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Interactive Controls
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Actions", systemImage: "play.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                Button(action: {
                                    Task {
                                        await testManager.runSwiftTests(forProject: project)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "play.shield.fill")
                                        Text("Run 'swift test'")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .disabled(testManager.isRunning)

                                Button(action: {
                                    testManager.cancelTests()
                                }) {
                                    HStack {
                                        Image(systemName: "stop.fill")
                                        Text("Cancel Run")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(!testManager.isRunning)

                                Spacer()

                                Button("Clear Results") {
                                    testManager.clearResults()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: Expandable Console Output
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Console & Live Log Streaming", systemImage: "terminal.fill")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                Spacer()

                                Button {
                                    let text = testManager.consoleOutput
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                } label: {
                                    Label("Copy Output", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .font(.caption)

                                Divider().frame(height: 12)

                                Button {
                                    exportLogs()
                                } label: {
                                    Label("Export Logs", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                            }

                            // Search bar inside console results
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Filter console output...", text: $searchConsoleQuery)
                                    .textFieldStyle(.plain)
                                if !searchConsoleQuery.isEmpty {
                                    Button {
                                        searchConsoleQuery = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if filteredConsoleOutput.isEmpty {
                                            Text("No output logged yet. Run tests to see output.")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text(filteredConsoleOutput)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.white)
                                                .textSelection(.enabled)
                                                .lineSpacing(4)
                                                .id("console_bottom")
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                }
                                .frame(height: 300)
                                .background(Color.black.opacity(0.85))
                                .cornerRadius(8)
                                .onChange(of: testManager.consoleOutput) { _, _ in
                                    if autoScrollConsole {
                                        withAnimation {
                                            proxy.scrollTo("console_bottom", anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Test Center")
        }
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.utf8PlainText]
        panel.nameFieldStringValue = "swift-test-run.log"
        panel.message = "Choose location to export test logs"

        if panel.runModal() == .OK, let url = panel.url {
            try? testManager.consoleOutput.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
