import SwiftUI
import YcodeBuild
import YcodeUI

struct BuildDiagnosticsView: View {
    @State private var buildManager = XcodeBuildManager.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Build Status")
                        .font(.headline)
                    Spacer()
                    Text(buildManager.currentStatus.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(statusColor)
                }

                HStack(spacing: 16) {
                    Text("Duration: \(String(format: "%.1f", buildManager.buildDuration))s")
                    Text("Warnings: \(buildManager.warningsCount)")
                    Text("Errors: \(buildManager.errorsCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !buildManager.buildLogs.isEmpty {
                    Button("Clear Logs") {
                        buildManager.buildLogs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if buildManager.buildLogs.isEmpty {
                ContentUnavailableView(
                    "No Build Logs Yet",
                    systemImage: "hammer",
                    description: Text("No build has run in this session. Live xcodebuild output will appear here once a build starts.")
                )
            } else {
                List(Array(buildManager.buildLogs.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: iconForLine(line))
                            .foregroundStyle(colorForLine(line))
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
            }
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("Build Diagnostics")
    }

    private var statusColor: Color {
        switch buildManager.currentStatus {
        case .succeeded: return .green
        case .failed, .toolNotFound, .permissionFailure, .invalidProject: return .red
        case .building: return .orange
        case .cancelled: return .yellow
        case .idle: return .secondary
        }
    }

    private func iconForLine(_ line: String) -> String {
        let lower = line.lowercased()
        if lower.contains("error:") { return "xmark.circle.fill" }
        if lower.contains("warning:") { return "exclamationmark.triangle.fill" }
        return "info.circle.fill"
    }

    private func colorForLine(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error:") { return .red }
        if lower.contains("warning:") { return .orange }
        return .secondary
    }
}
