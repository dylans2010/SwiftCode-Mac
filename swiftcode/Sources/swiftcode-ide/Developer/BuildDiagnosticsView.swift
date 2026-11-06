// BuildDiagnosticsView.swift
//
// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/BuildDiagnosticsView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: PARTIAL at bc28f653 (BuildLogsView is a different, real log viewer; this diagnostics
// step-list view was absent). Confirmed genuinely missing at 7ac654a9: no equivalent view exists.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
//
// CLEANUP (2026-11-06, C12): Legacy's `logs` array was hardcoded sample
// entries ("Resolving Swift Packages" 1.2s, "Compiling Module
// SwiftCodeCore" 4.5s, "Compiling Main Target" 12.1s + a fake warning,
// "Linking SwiftCode.app" 2.1s) — a build that never ran, presented as
// diagnostics. Replaced with the live log stream:
// XcodeBuildManager.shared.buildLogs (real xcodebuild output lines
// appended as the build runs), plus the manager's live status,
// duration, warning and error counts. Until a build has run the view
// shows an honest empty state instead of sample rows. Lines are
// classified only by their real content ("error:" / "warning:").

import SwiftUI
import SwiftCodeBuild
import SwiftCodeUI

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
                // Indexed by position: xcodebuild output can contain
                // identical lines, so the line text itself is not a
                // usable row identity.
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

    /// Classifies a live log line by its real content only.
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
