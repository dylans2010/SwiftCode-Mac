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
                // Sticky Header / Toolbar Panel
                stickyToolbarView

                Divider()

                ScrollView {
                    VStack(spacing: 24) {
                        // Card 1: Build Status Metrics
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Xcode Build Summary", systemImage: "hammer.fill")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Spacer()
                                }

                                buildStatusHeader
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 2: Build Configurations (Adaptive Desktop Layout)
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Target Specifications", systemImage: "gearshape.fill")
                                        .font(.headline)
                                        .foregroundColor(.purple)
                                    Spacer()
                                }

                                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                                    GridRow {
                                        Text("Active Build Scheme")
                                            .foregroundColor(.secondary)
                                        Text("Primary Target Scheme")
                                            .fontWeight(.semibold)

                                        Text("Build SDK")
                                            .foregroundColor(.secondary)
                                        Text("macOS / iOS (Simulator)")
                                            .fontWeight(.semibold)
                                    }

                                    GridRow {
                                        Text("Optimization Level")
                                            .foregroundColor(.secondary)
                                        Text("-Onone (Debug)")
                                            .fontWeight(.semibold)

                                        Text("Toolchain Location")
                                            .foregroundColor(.secondary)
                                        Text(buildManager.getXcodeBuildPath())
                                            .font(.system(.body, design: .monospaced))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 3: Collapsible Errors Group
                        if !errorLogs.isEmpty {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Button {
                                        withAnimation { showErrorsGroup.toggle() }
                                    } label: {
                                        HStack {
                                            Label("Errors Detected (\(errorLogs.count))", systemImage: "exclamationmark.octagon.fill")
                                                .font(.headline)
                                                .foregroundColor(.red)
                                            Spacer()
                                            Image(systemName: showErrorsGroup ? "chevron.up" : "chevron.down")
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    if showErrorsGroup {
                                        Divider()
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(errorLogs) { log in
                                                HStack(alignment: .top, spacing: 10) {
                                                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                        .font(.system(.caption, design: .monospaced))
                                                        .foregroundColor(.secondary)

                                                    Text(log.message)
                                                        .font(.system(.body, design: .monospaced))
                                                        .foregroundColor(.red)
                                                        .textSelection(.enabled)
                                                }
                                                .padding(6)
                                                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                            }
                                        }
                                    }
                                }
                                .padding()
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }

                        // Card 4: Collapsible Warnings Group
                        if !warningLogs.isEmpty {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Button {
                                        withAnimation { showWarningsGroup.toggle() }
                                    } label: {
                                        HStack {
                                            Label("Warnings Detected (\(warningLogs.count))", systemImage: "exclamationmark.triangle.fill")
                                                .font(.headline)
                                                .foregroundColor(.yellow)
                                            Spacer()
                                            Image(systemName: showWarningsGroup ? "chevron.up" : "chevron.down")
                                                .foregroundStyle(.yellow)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    if showWarningsGroup {
                                        Divider()
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(warningLogs) { log in
                                                HStack(alignment: .top, spacing: 10) {
                                                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                        .font(.system(.caption, design: .monospaced))
                                                        .foregroundColor(.secondary)

                                                    Text(log.message)
                                                        .font(.system(.body, design: .monospaced))
                                                        .foregroundColor(.yellow)
                                                        .textSelection(.enabled)
                                                }
                                                .padding(6)
                                                .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                            }
                                        }
                                    }
                                }
                                .padding()
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }

                        // Card 5: Full Console Outputs Group
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Button {
                                    withAnimation { showFullConsole.toggle() }
                                } label: {
                                    HStack {
                                        Label("Console Outputs Log Trace", systemImage: "terminal.fill")
                                            .font(.headline)
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
                                            LazyVStack(alignment: .leading, spacing: 4) {
                                                if filteredStructuredLogs.isEmpty {
                                                    VStack(spacing: 12) {
                                                        Spacer()
                                                        Image(systemName: "doc.text.magnifyingglass")
                                                            .font(.system(size: 32))
                                                            .foregroundStyle(.secondary)
                                                        Text("No matching build logs")
                                                            .font(.headline)
                                                            .foregroundStyle(.secondary)
                                                        Spacer()
                                                    }
                                                    .frame(maxWidth: .infinity, minHeight: 200)
                                                } else {
                                                    ForEach(Array(filteredStructuredLogs.enumerated()), id: \.offset) { index, log in
                                                        HStack(alignment: .top, spacing: 8) {
                                                            Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                                                .font(.system(.caption2, design: .monospaced))
                                                                .foregroundColor(.secondary.opacity(0.7))

                                                            Text(log.message)
                                                                .font(.system(.caption, design: .monospaced))
                                                                .foregroundStyle(log.severity.color)
                                                                .textSelection(.enabled)
                                                        }
                                                        .id(index)
                                                    }
                                                }
                                            }
                                            .padding()
                                        }
                                        .frame(height: 380)
                                        .background(Color.black.opacity(0.85))
                                        .cornerRadius(8)
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
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                    .padding(24)
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Xcode Build Center")
        }
        .frame(minWidth: 800, idealWidth: 950, maxWidth: .infinity, minHeight: 600, idealHeight: 750, maxHeight: .infinity)
    }

    private var stickyToolbarView: some View {
        HStack(spacing: 16) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search build logs...", text: $searchLogQuery)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .frame(width: 250)

            Picker("Filter Logs", selection: $filterMode) {
                ForEach(LogFilterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Toggle("Auto-scroll", isOn: $autoScrollToBottom)
                .toggleStyle(.checkbox)

            Spacer()

            Button(action: {
                let text = buildManager.buildLogs.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }) {
                Label("Copy Raw Logs", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            if buildManager.isBuilding {
                Button("Cancel Build") {
                    buildManager.cancelBuild()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
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
