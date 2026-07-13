import SwiftUI
import AppKit

@MainActor
struct StructuredBuildLog: Identifiable, Sendable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let severity: Severity

    enum Severity: String, Sendable, CaseIterable, Identifiable {
        case error = "Error"
        case warning = "Warning"
        case system = "System"
        case info = "Info"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .error: return "exclamationmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .system: return "cpu.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .error: return .red
            case .warning: return .yellow
            case .system: return .cyan
            case .info: return .secondary
            }
        }
    }
}

@MainActor
struct XcodeBuildLogView: View {
    @State private var searchLogQuery = ""
    @State private var autoScrollToBottom = true
    @State private var filterMode: LogFilterMode = .all

    // Collapsible section states
    @State private var showErrorsGroup = true
    @State private var showWarningsGroup = true
    @State private var showFullConsole = true

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

    private var structuredLogs: [StructuredBuildLog] {
        buildManager.buildLogs.map { line in
            let lower = line.lowercased()
            let severity: StructuredBuildLog.Severity
            if lower.contains("error:") || lower.hasPrefix("error:") || lower.hasPrefix("[error]") {
                severity = .error
            } else if lower.contains("warning:") || lower.hasPrefix("warning:") {
                severity = .warning
            } else if lower.hasPrefix("[system]") {
                severity = .system
            } else {
                severity = .info
            }
            return StructuredBuildLog(message: line, severity: severity)
        }
    }

    private var filteredStructuredLogs: [StructuredBuildLog] {
        var logs = structuredLogs

        if !searchLogQuery.isEmpty {
            logs = logs.filter { $0.message.localizedCaseInsensitiveContains(searchLogQuery) }
        }

        switch filterMode {
        case .all:
            return logs
        case .errors:
            return logs.filter { $0.severity == .error }
        case .warnings:
            return logs.filter { $0.severity == .warning }
        case .system:
            return logs.filter { $0.severity == .system }
        }
    }

    private var errorLogs: [StructuredBuildLog] {
        structuredLogs.filter { $0.severity == .error }
    }

    private var warningLogs: [StructuredBuildLog] {
        structuredLogs.filter { $0.severity == .warning }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Compact Sticky Header / Toolbar Panel
                stickyToolbarView

                Divider()

                ScrollView {
                    VStack(spacing: 14) {
                        // Card 1: Build Status Metrics
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                buildStatusHeader
                            }
                            .padding(10)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 2: Build Configurations (Adaptive Desktop Layout)
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Target Specifications", systemImage: "gearshape.fill")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.purple)
                                    Spacer()
                                }

                                Divider()

                                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                    GridRow {
                                        Text("Active Build Scheme")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("Primary Target Scheme")
                                            .font(.caption.bold())

                                        Text("Build SDK")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("macOS / iOS (Simulator)")
                                            .font(.caption.bold())
                                    }

                                    GridRow {
                                        Text("Optimization Level")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("-Onone (Debug)")
                                            .font(.caption.bold())

                                        Text("Toolchain Location")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(buildManager.getXcodeBuildPath())
                                            .font(.system(.caption, design: .monospaced))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(10)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 3: Collapsible Errors Group
                        if !errorLogs.isEmpty {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        withAnimation { showErrorsGroup.toggle() }
                                    } label: {
                                        HStack {
                                            Label("Errors Detected (\(errorLogs.count))", systemImage: "exclamationmark.octagon.fill")
                                                .font(.subheadline.bold())
                                                .foregroundColor(.red)
                                            Spacer()
                                            Image(systemName: showErrorsGroup ? "chevron.up" : "chevron.down")
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    if showErrorsGroup {
                                        Divider()
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(errorLogs) { log in
                                                HStack(alignment: .top, spacing: 8) {
                                                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                        .font(.system(.caption2, design: .monospaced))
                                                        .foregroundColor(.secondary)

                                                    Text(log.message)
                                                        .font(.system(.caption, design: .monospaced))
                                                        .foregroundColor(.red)
                                                        .textSelection(.enabled)
                                                }
                                                .padding(4)
                                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                            }
                                        }
                                    }
                                }
                                .padding(10)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }

                        // Card 4: Collapsible Warnings Group
                        if !warningLogs.isEmpty {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        withAnimation { showWarningsGroup.toggle() }
                                    } label: {
                                        HStack {
                                            Label("Warnings Detected (\(warningLogs.count))", systemImage: "exclamationmark.triangle.fill")
                                                .font(.subheadline.bold())
                                                .foregroundColor(.yellow)
                                            Spacer()
                                            Image(systemName: showWarningsGroup ? "chevron.up" : "chevron.down")
                                                .foregroundStyle(.yellow)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    if showWarningsGroup {
                                        Divider()
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(warningLogs) { log in
                                                HStack(alignment: .top, spacing: 8) {
                                                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                        .font(.system(.caption2, design: .monospaced))
                                                        .foregroundColor(.secondary)

                                                    Text(log.message)
                                                        .font(.system(.caption, design: .monospaced))
                                                        .foregroundColor(.yellow)
                                                        .textSelection(.enabled)
                                                }
                                                .padding(4)
                                                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                            }
                                        }
                                    }
                                }
                                .padding(10)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }

                        // Card 5: Full Console Outputs Group
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    withAnimation { showFullConsole.toggle() }
                                } label: {
                                    HStack {
                                        Label("Console Outputs Log Trace", systemImage: "terminal.fill")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.blue)
                                        Spacer()
                                        Image(systemName: showFullConsole ? "chevron.up" : "chevron.down")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .buttonStyle(.plain)

                                if showFullConsole {
                                    Divider()

                                    ScrollViewReader { proxy in
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 3) {
                                                if filteredStructuredLogs.isEmpty {
                                                    VStack(spacing: 10) {
                                                        Spacer()
                                                        Image(systemName: "doc.text.magnifyingglass")
                                                            .font(.system(size: 24))
                                                            .foregroundStyle(.secondary)
                                                        Text("No matching build logs")
                                                            .font(.subheadline.bold())
                                                            .foregroundStyle(.secondary)
                                                        Spacer()
                                                    }
                                                    .frame(maxWidth: .infinity, minHeight: 180)
                                                } else {
                                                    ForEach(Array(filteredStructuredLogs.enumerated()), id: \.offset) { index, log in
                                                        HStack(alignment: .top, spacing: 6) {
                                                            Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                                .font(.system(size: 9, design: .monospaced))
                                                                .foregroundColor(.secondary.opacity(0.6))

                                                            // Severity indicator dot
                                                            Circle()
                                                                .fill(log.severity.color)
                                                                .frame(width: 5, height: 5)
                                                                .padding(.top, 5)

                                                            Text(log.message)
                                                                .font(.system(size: 10, design: .monospaced))
                                                                .foregroundStyle(log.severity.color)
                                                                .textSelection(.enabled)
                                                        }
                                                        .id(index)
                                                    }
                                                }
                                            }
                                            .padding(8)
                                        }
                                        .frame(height: 320)
                                        .background(Color.black.opacity(0.85))
                                        .cornerRadius(6)
                                        .onChange(of: filteredStructuredLogs.count) { _, newCount in
                                            if autoScrollToBottom && newCount > 0 {
                                                withAnimation {
                                                    proxy.scrollTo(newCount - 1, anchor: .bottom)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(10)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                    .padding(16)
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Xcode Build Center")
        }
        .frame(minWidth: 780, idealWidth: 880, maxWidth: .infinity, minHeight: 520, idealHeight: 650, maxHeight: .infinity)
    }

    private var stickyToolbarView: some View {
        HStack(spacing: 12) {
            // Search field (compact)
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search logs...", text: $searchLogQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .frame(width: 180)

            // Segmented filter (compact)
            Picker("", selection: $filterMode) {
                ForEach(LogFilterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 260)

            Toggle("Auto-scroll", isOn: $autoScrollToBottom)
                .font(.caption)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Spacer()

            // Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    let text = buildManager.buildLogs.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }) {
                    Label("Copy Logs", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if buildManager.isBuilding {
                    Button("Cancel Build") {
                        buildManager.cancelBuild()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var buildStatusHeader: some View {
        HStack(spacing: 16) {
            // Status Badge (compact)
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(statusColor(buildManager.currentStatus).opacity(0.12))
                        .frame(width: 32, height: 32)

                    if buildManager.isBuilding {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: statusIcon(buildManager.currentStatus))
                            .font(.headline)
                            .foregroundStyle(statusColor(buildManager.currentStatus))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("BUILD STATUS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(buildManager.currentStatus.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(statusColor(buildManager.currentStatus))
                }
            }
            .frame(width: 160, alignment: .leading)

            Divider().frame(height: 24)

            // Duration Metric
            VStack(alignment: .leading, spacing: 2) {
                Text("DURATION")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f s", buildManager.buildDuration))
                    .font(.subheadline.bold())
            }
            .frame(width: 80, alignment: .leading)

            Divider().frame(height: 24)

            // Error Metric
            VStack(alignment: .leading, spacing: 2) {
                Text("ERRORS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(buildManager.errorsCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(buildManager.errorsCount > 0 ? .red : .primary)
            }
            .frame(width: 60, alignment: .leading)

            Divider().frame(height: 24)

            // Warning Metric
            VStack(alignment: .leading, spacing: 2) {
                Text("WARNINGS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(buildManager.warningsCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(buildManager.warningsCount > 0 ? .yellow : .primary)
            }
            .frame(width: 60, alignment: .leading)
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
