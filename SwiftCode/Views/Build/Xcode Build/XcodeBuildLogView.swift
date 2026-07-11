import SwiftUI

@MainActor
struct XcodeBuildLogView: View {
    @State private var searchLogQuery = ""
    @State private var autoScrollToBottom = true
    @State private var filterMode: LogFilterMode = .all

    @Environment(\.dismiss) private var dismiss

    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
    }

    enum LogFilterMode: String, CaseIterable, Identifiable {
        case all = "All Logs"
        case errors = "Errors"
        case warnings = "Warnings"
        case system = "System"

        var id: String { rawValue }
    }

    private var filteredLogs: [String] {
        var logs = buildManager.buildLogs

        // Apply raw text search if any
        if !searchLogQuery.isEmpty {
            logs = logs.filter { $0.localizedCaseInsensitiveContains(searchLogQuery) }
        }

        // Apply filters
        switch filterMode {
        case .all:
            return logs
        case .errors:
            return logs.filter {
                let lower = $0.lowercased()
                return lower.contains("error:") || lower.hasPrefix("error:") || lower.hasPrefix("[error]")
            }
        case .warnings:
            return logs.filter {
                let lower = $0.lowercased()
                return lower.contains("warning:") || lower.hasPrefix("warning:")
            }
        case .system:
            return logs.filter { $0.hasPrefix("[system]") }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Status Hub Card
                    GroupBox {
                        buildStatusHeader
                            .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Search & Filter Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Log Configuration", systemImage: "slider.horizontal.3")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                    TextField("Search build logs...", text: $searchLogQuery)
                                        .textFieldStyle(.plain)
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))

                                Picker("Filter", selection: $filterMode) {
                                    ForEach(LogFilterMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 320)

                                Toggle("Auto-scroll", isOn: $autoScrollToBottom)
                                    .toggleStyle(.checkbox)

                                Button(action: {
                                    let text = buildManager.buildLogs.joined(separator: "\n")
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                }) {
                                    Label("Copy Logs", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Build Logs Output Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Build Logs Terminal Output", systemImage: "terminal.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 4) {
                                        if filteredLogs.isEmpty {
                                            VStack(spacing: 12) {
                                                Spacer()
                                                Image(systemName: "doc.text.magnifyingglass")
                                                    .font(.system(size: 32))
                                                    .foregroundStyle(.secondary)
                                                Text("No matching logs found")
                                                    .font(.headline)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 250)
                                        } else {
                                            ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, log in
                                                Text(log)
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(logColor(for: log))
                                                    .textSelection(.enabled)
                                                    .id(index)
                                            }
                                        }
                                    }
                                    .padding()
                                }
                                .frame(minHeight: 300, maxHeight: 500)
                                .background(Color.black)
                                .cornerRadius(8)
                                .onChange(of: filteredLogs.count) { _, newCount in
                                    if autoScrollToBottom && newCount > 0 {
                                        withAnimation {
                                            proxy.scrollTo(newCount - 1, anchor: .bottom)
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
            .navigationTitle("Xcode Build Center")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close Build Center") {
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
        .frame(minWidth: 700, idealWidth: 850, maxWidth: .infinity, minHeight: 500, idealHeight: 600, maxHeight: .infinity)
    }

    private var buildStatusHeader: some View {
        HStack(spacing: 24) {
            // Visual Status Badge
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(statusColor(buildManager.currentStatus).opacity(0.15))
                        .frame(width: 52, height: 52)

                    if buildManager.isBuilding {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: statusIcon(buildManager.currentStatus))
                            .font(.title2)
                            .foregroundStyle(statusColor(buildManager.currentStatus))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("BUILD STATUS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(buildManager.currentStatus.rawValue)
                        .font(.title3.bold())
                        .foregroundStyle(statusColor(buildManager.currentStatus))
                }
            }
            .frame(width: 220, alignment: .leading)

            Divider().frame(height: 40)

            // Duration Metric
            VStack(alignment: .leading, spacing: 4) {
                Text("DURATION")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f s", buildManager.buildDuration))
                    .font(.title3.bold())
            }
            .frame(width: 100, alignment: .leading)

            Divider().frame(height: 40)

            // Error Metric
            VStack(alignment: .leading, spacing: 4) {
                Text("ERRORS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(buildManager.errorsCount)")
                    .font(.title3.bold())
                    .foregroundStyle(buildManager.errorsCount > 0 ? .red : .primary)
            }
            .frame(width: 80, alignment: .leading)

            Divider().frame(height: 40)

            // Warning Metric
            VStack(alignment: .leading, spacing: 4) {
                Text("WARNINGS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(buildManager.warningsCount)")
                    .font(.title3.bold())
                    .foregroundStyle(buildManager.warningsCount > 0 ? .yellow : .primary)
            }
            .frame(width: 80, alignment: .leading)

            Spacer()

            // Toolchain Details
            VStack(alignment: .trailing, spacing: 4) {
                Text("XCODEBUILD TOOLCHAIN")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(buildManager.getXcodeBuildPath())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func logColor(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error:") || lower.hasPrefix("error:") || lower.hasPrefix("[error]") {
            return .red
        } else if lower.contains("warning:") || lower.hasPrefix("warning:") {
            return .yellow
        } else if lower.hasPrefix("[system]") {
            return .cyan
        } else {
            return .white.opacity(0.85)
        }
    }

    private func statusIcon(_ status: XcodeBuildManager.BuildStatus) -> String {
        switch status {
        case .idle: return "play.circle"
        case .building: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "multiply.circle.fill"
        default: return "exclamationmark.circle.fill"
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
