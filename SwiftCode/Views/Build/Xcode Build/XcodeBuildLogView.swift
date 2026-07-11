import SwiftUI

struct XcodeBuildLogView: View {
    @State private var searchLogQuery = ""
    @State private var autoScrollToBottom = true

    @Environment(\.dismiss) private var dismiss

    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
    }

    private var filteredLogs: [String] {
        if searchLogQuery.isEmpty {
            return buildManager.buildLogs
        } else {
            return buildManager.buildLogs.filter { $0.localizedCaseInsensitiveContains(searchLogQuery) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Status Bar
                buildStatusBar
                    .padding()
                    .background(Color.secondary.opacity(0.05))

                Divider()

                // Filter / Search Toolbar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search logs...", text: $searchLogQuery)
                            .textFieldStyle(.plain)
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    Toggle("Auto-scroll", isOn: $autoScrollToBottom)
                        .toggleStyle(.checkbox)

                    Button("Copy All") {
                        let text = buildManager.buildLogs.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

                Divider()

                // Logs Display Area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, log in
                                Text(log)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(logColor(for: log))
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .padding()
                    }
                    .background(Color.black)
                    .onChange(of: filteredLogs.count) { _, newCount in
                        if autoScrollToBottom && newCount > 0 {
                            withAnimation {
                                proxy.scrollTo(newCount - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Live Build Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close Logs") {
                        dismiss()
                    }
                }

                if buildManager.isBuilding {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Cancel Build") {
                            buildManager.cancelBuild()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }

    private var buildStatusBar: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Build Status")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if buildManager.isBuilding {
                        ProgressView().controlSize(.small)
                    }
                    Text(buildManager.currentStatus.rawValue)
                        .font(.headline)
                        .foregroundStyle(statusColor(buildManager.currentStatus))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Duration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f s", buildManager.buildDuration))
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Errors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(buildManager.errorsCount)")
                    .font(.headline)
                    .foregroundStyle(buildManager.errorsCount > 0 ? .red : .primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Warnings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(buildManager.warningsCount)")
                    .font(.headline)
                    .foregroundStyle(buildManager.warningsCount > 0 ? .yellow : .primary)
            }

            Spacer()
        }
    }

    private func logColor(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error:") || lower.hasPrefix("error:") {
            return .red
        } else if lower.contains("warning:") || lower.hasPrefix("warning:") {
            return .yellow
        } else if lower.hasPrefix("[system]") {
            return .cyan
        } else if lower.hasPrefix("[error]") {
            return .red
        } else {
            return .white.opacity(0.85)
        }
    }

    private func statusColor(_ status: XcodeBuildManager.BuildStatus) -> Color {
        switch status {
        case .idle: return .secondary
        case .building: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return .red
        }
    }
}
