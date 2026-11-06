import SwiftUI
import AppKit

// MARK: - Diagnostics: structured log, exportable as plain text

public struct ExtensionDiagnosticsView: View {
    @StateObject private var viewModel = ExtV2DiagnosticsViewModel()
    @State private var copied = false
    @State private var testReport: RuntimeTestSuiteReport?
    @State private var isTesting = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Refresh") { viewModel.refresh() }
                Button("Clear") { viewModel.clear() }
                Button(isTesting ? "Testing…" : "Run self-tests") {
                    Task {
                        isTesting = true
                        testReport = await ExtV2TestSuite.shared.runAllTests()
                        isTesting = false
                    }
                }
                .disabled(isTesting)
                Button(copied ? "Copied" : "Copy report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ExtV2DiagnosticsService.shared.exportReport(), forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copied = false
                    }
                }
                Spacer()
            }
            .padding()
            Divider()
            if let testReport {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Self-tests: \(testReport.passedTests)/\(testReport.totalTests) passed")
                        .font(.subheadline.bold())
                    ForEach(testReport.results) { result in
                        HStack {
                            Image(systemName: result.passed ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(result.passed ? .green : .red)
                            Text(result.testName).font(.callout)
                            Spacer()
                            if !result.passed {
                                Text(result.message).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
                .padding()
                Divider()
            }
            if viewModel.entries.isEmpty {
                ContentUnavailableView("No diagnostics yet", systemImage: "stethoscope", description: Text("Activation failures, host crashes, and permission changes appear here."))
            } else {
                List(viewModel.entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.level.rawValue.uppercased())
                                .font(.caption2.bold())
                                .foregroundStyle(levelColor(entry.level))
                            if let extensionId = entry.extensionId {
                                Text(extensionId).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.timestamp, style: .time).font(.caption).foregroundStyle(.tertiary)
                        }
                        Text(entry.message).font(.callout)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .onAppear { viewModel.refresh() }
    }

    private func levelColor(_ level: ExtV2DiagnosticLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
