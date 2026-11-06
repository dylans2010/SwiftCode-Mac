import Foundation
import SwiftUI
import AppKit

// MARK: - SDKStudioLogsView
//
// Studio log inspector (spec Docs/Intro-to-SDK.md §16): three panes over the
// real log pipelines —
//   - User:       `SDKUserLogger.shared` sanitized in-memory entries (§16.1).
//   - Developer:  `SDKDeveloperLogger.shared` verbose JSON lines from
//                 `~/.swiftcode/logs/developer-sdk.log` (§16.2).
//   - Audit:      `SDKAuditLog.shared` durable security audit events (§16.3).
//
// All data shown is live from the real loggers; there is no sample content.

public struct SDKStudioLogsView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case user = "User"
        case developer = "Developer"
        case audit = "Audit"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .user

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Logs", selection: $segment) {
                ForEach(Segment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            Divider().padding(.top)

            switch segment {
            case .user:
                UserLogsPane()
            case .developer:
                DeveloperLogsPane()
            case .audit:
                AuditLogsPane()
            }
        }
    }
}

// MARK: - User logs pane (§16.1)

private struct UserLogsPane: View {
    @State private var entries: [SDKUserLogEntry] = []
    @State private var searchText = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter by correlation ID", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { _, _ in reload() }
                Button("Refresh") { reload() }
            }
            .padding()
            .liquidGlass(style: .subtle, cornerRadius: 8)
            .padding(6)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }

            if entries.isEmpty {
                emptyState("No entries yet")
            } else {
                List(entries, id: \.correlationIdAndTimestamp) { entry in
                    userEntryRow(entry)
                }
            }
        }
        .task { reload() }
    }

    private func reload() {
        // `SDKUserLogger` reads are synchronous in-memory snapshots.
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        entries = query.isEmpty
            ? SDKUserLogger.shared.recentEntries()
            : SDKUserLogger.shared.entries(matching: query)
        errorMessage = nil
    }

    private func userEntryRow(_ entry: SDKUserLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                levelIcon(for: entry.level)
                Text(entry.timestamp, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if !entry.correlationId.isEmpty {
                    correlationChip(entry.correlationId)
                }
            }
            Text(entry.title)
                .font(.headline)
            Text(entry.message)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private func levelIcon(for level: SDKUserLogLevel) -> some View {
        switch level {
        case .info:
            Label("Info", systemImage: "info.circle")
                .foregroundStyle(.blue)
        case .warning:
            Label("Warning", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .error:
            Label("Error", systemImage: "xmark.octagon")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Developer logs pane (§16.2)

private struct DeveloperLogsPane: View {
    @State private var searchText = ""
    @State private var lines: [String] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var errorMessage: String?

    private var logLocation: URL { SDKDeveloperLogger.shared.logFileLocation }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Correlation ID (e.g. ERR-8F3A29)", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .onSubmit { search() }
                    Button("Search") { search() }
                        .disabled(isLoading || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Text(logLocation.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([logLocation])
                    }
                    .buttonStyle(.link)
                }
            }
            .padding()

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }

            if isLoading {
                HStack {
                    ProgressView()
                    Text("Reading log file…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasSearched {
                emptyState("Enter a correlation ID and press Search")
            } else if lines.isEmpty {
                emptyState("No entries yet")
            } else {
                ScrollView {
                    Text(lines.joined(separator: "\n"))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
            }
        }
    }

    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            let result = await SDKDeveloperLogger.shared.fetchEntries(correlationId: query)
            isLoading = false
            hasSearched = true
            lines = result
        }
    }
}

// MARK: - Audit logs pane (§16.3)

private struct AuditLogsPane: View {
    @State private var events: [SDKAuditEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Security audit events")
                    .font(.headline)
                Spacer()
                Button("Refresh") { reload() }
                    .disabled(isLoading)
            }
            .padding()

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }

            if isLoading {
                HStack {
                    ProgressView()
                    Text("Reading audit log…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                emptyState("No entries yet")
            } else {
                List(events, id: \.id) { event in
                    auditEventRow(event)
                }
            }
        }
        .task { reload() }
    }

    private func reload() {
        isLoading = true
        errorMessage = nil
        Task {
            let result = await SDKAuditLog.shared.recentEvents(limit: 200)
            isLoading = false
            events = result
        }
    }

    private func auditEventRow(_ event: SDKAuditEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                auditTypeIcon(for: event.type)
                Text(humanized(event.type.rawValue))
                    .font(.headline)
                Spacer()
                Text(event.timestamp, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let extensionID = event.extensionID, !extensionID.isEmpty {
                    Label(extensionID, systemImage: "puzzlepiece.extension")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let capability = event.capabilityRaw, !capability.isEmpty {
                    Label(capability, systemImage: "key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let correlationId = event.correlationId, !correlationId.isEmpty {
                    correlationChip(correlationId)
                }
            }
            if let detail = event.detail, !detail.isEmpty {
                Text(detail)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func auditTypeIcon(for type: SDKAuditEventType) -> some View {
        let name: String
        let color: Color
        switch type {
        case .permissionRequested:
            name = "hand.raised"; color = .blue
        case .permissionGranted:
            name = "checkmark.shield"; color = .green
        case .permissionDenied, .permissionRevoked, .assistDenied,
             .cloudModelDenied, .apiKeyScopeFailure, .apiKeyAuthFailure,
             .runtimeTerminated, .securityPermissionDenied:
            name = "xmark.shield"; color = .red
        case .apiKeyCreated:
            name = "key.badge.plus"; color = .green
        case .securityValueAdded:
            name = "key.badge.plus"; color = .green
        case .securityValueUsed:
            name = "key"; color = .blue
        case .apiKeyRevoked:
            name = "key.slash"; color = .orange
        case .entitlementGranted:
            name = "checkmark.seal"; color = .green
        case .entitlementRevoked:
            name = "xmark.seal"; color = .orange
        case .extensionInstalled, .extensionUpdated:
            name = "square.and.arrow.down"; color = .blue
        case .extensionDisabled, .extensionUninstalled,
             .securityValueDeleted, .securityValuesWipedOnUninstall:
            name = "trash"; color = .orange
        }
        return Image(systemName: name).foregroundStyle(color)
    }
}

// MARK: - Shared chrome

private func emptyState(_ message: String) -> some View {
    ContentUnavailableView {
        Label(message, systemImage: "doc.text.magnifyingglass")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

private func correlationChip(_ correlationId: String) -> some View {
    Text(correlationId)
        .font(.caption2.monospaced())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .textSelection(.enabled)
}

private func humanized(_ rawValue: String) -> String {
    rawValue
        .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        .capitalized
}

// Stable list identity for `SDKUserLogEntry` (no `id` field on the type).
private extension SDKUserLogEntry {
    var correlationIdAndTimestamp: String {
        "\(correlationId)-\(timestamp.timeIntervalSinceReferenceDate)-\(title)-\(message.hashValue)"
    }
}
