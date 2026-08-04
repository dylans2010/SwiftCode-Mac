import SwiftUI

struct DiagnosticsView: View {
    @State private var dm = DiagnosticsManager.shared
    @State private var showScanningSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workspace Diagnostics")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Identify broken file references, security flaws, deprecated APIs, and package inconsistencies.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    Task {
                        await dm.scanWorkspace()
                    }
                } label: {
                    Label(dm.isScanning ? "Scanning..." : "Rescan Diagnostics", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(dm.isScanning)
            }
            .padding(16)

            Divider()

            if dm.isScanning {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Scanning files, folder trees, assets, and packages...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if dm.issues.isEmpty {
                ContentUnavailableView {
                    Label("No Diagnostics Issues Found", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } description: {
                    Text("Your workspace, configurations, package definitions, and asset references are healthy.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(dm.issues) { issue in
                    GroupBox {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: iconForCategory(issue.category))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(colorForCategory(issue.category))
                                .frame(width: 24, height: 24)
                                .background(colorForCategory(issue.category).opacity(0.12))
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(issue.category)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(colorForCategory(issue.category))
                                    Spacer()
                                    if let path = issue.filePath {
                                        Text(path)
                                            .font(.caption2, design: .monospaced)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Text(issue.message)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Suggested Fix:")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                    Text(issue.suggestedFix)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                            }
                        }
                        .padding(4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            if dm.lastScanDate == nil {
                Task {
                    await dm.scanWorkspace()
                }
            }
        }
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Broken Reference": return "folder.badge.minus"
        case "Deprecated API": return "exclamationmark.shield"
        case "Signing": return "key"
        case "Concurrency": return "arrow.3.trianglepath"
        default: return "ant"
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Broken Reference": return .red
        case "Deprecated API": return .orange
        case "Signing": return .purple
        case "Concurrency": return .blue
        default: return .secondary
        }
    }
}
