import SwiftUI
import SwiftCodeIDEShell

/// Workspace Operations hub — Legacy's `OperationsDashboardView` +
/// `OperationsSidebarView` + the 16 panel views, rebuilt in SwiftCode style.
///
/// The hub is a `NavigationSplitView` over `OperationsCoordinator`. Panels
/// that need a workspace take `workspaceURL` (nil = workspace-independent
/// panels only); every number shown is read from a real store or measured
/// live — an empty store shows an empty state, never invented rows.
public struct OperationsDashboardView: View {
    @State private var coordinator = OperationsCoordinator.shared
    public var workspaceURL: URL?

    @State private var securityFindings: [OperationsSecretFinding] = []
    @State private var securityScanned = false
    @State private var aiReport: String?

    public init(workspaceURL: URL? = nil) {
        self.workspaceURL = workspaceURL
    }

    public var body: some View {
        NavigationSplitView {
            List(OperationsPanel.allCases, selection: $coordinator.selectedPanel) { panel in
                Label(panel.rawValue, systemImage: panel.icon).tag(panel)
            }
            .listStyle(.sidebar)
            .navigationTitle("Operations")
        } detail: {
            panelView
                .navigationTitle(coordinator.selectedPanel.rawValue)
        }
        .task { await coordinator.refreshRegistry() }
    }

    @ViewBuilder
    private var panelView: some View {
        switch coordinator.selectedPanel {
        case .dashboard: dashboardPanel
        case .projectRegistry: registryPanel
        case .archives: archivesPanel
        case .buildHistory: buildHistoryPanel
        case .diagnostics: diagnosticsPanel
        case .dependencies: dependenciesPanel
        case .storage: storagePanel
        case .security: securityPanel
        case .aiReports: aiReportsPanel
        case .health: healthPanel
        case .logs: logsPanel
        case .timeline: timelinePanel
        case .search: searchPanel
        case .queue: queuePanel
        case .notifications: notificationsPanel
        case .preferences: preferencesPanel
        }
    }

    private var dashboardPanel: some View {
        let builds = coordinator.builds.buildRecords
        let errors = builds.reduce(0) { $0 + $1.errors }
        let warnings = builds.reduce(0) { $0 + $1.warnings }
        return List {
            Section("Overview") {
                LabeledContent("Registered projects", value: "\(coordinator.registryEntries.count)")
                LabeledContent("Recorded builds", value: "\(builds.count)")
                LabeledContent("Build success rate", value: builds.isEmpty ? "No builds recorded" : "\(Int(coordinator.builds.successRate * 100))%")
                LabeledContent("Build errors / warnings", value: "\(errors) / \(warnings)")
                LabeledContent("Archives", value: "\(coordinator.archives.archives.count)")
                LabeledContent("Unread notifications", value: "\(coordinator.notifications.unreadCount)")
                LabeledContent("Queued operations", value: "\(coordinator.queue.activeTaskCount)")
            }
            Section("Recent builds") {
                if builds.isEmpty {
                    Text("No builds recorded yet. Builds are recorded here when the IDE runs one.").foregroundStyle(.secondary)
                } else {
                    ForEach(builds.prefix(5)) { record in
                        VStack(alignment: .leading) {
                            Text(record.projectName).font(.headline)
                            Text("\(record.date, style: .relative) · \(record.status) · \(record.configuration)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var registryPanel: some View {
        List(coordinator.registryEntries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).font(.headline)
                Text(entry.rootURL.path).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text("Git: \(entry.gitStatus)").font(.caption)
                    Text("Package: \(entry.packageStatus)").font(.caption)
                    Text("Last opened \(entry.lastOpened, style: .relative)").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if coordinator.registryEntries.isEmpty {
                ContentUnavailableView("No projects registered", systemImage: "folder", description: Text("Open a project and it appears here."))
            }
        }
    }

    private var archivesPanel: some View {
        List(coordinator.archives.archives) { archive in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(archive.projectName) \(archive.version) (\(archive.buildNumber))").font(.headline)
                Text("\(archive.date, style: .date) · \(archive.configuration) · \(archive.commit)").font(.caption).foregroundStyle(.secondary)
                Text("Binary: \(ByteCountFormatter.string(fromByteCount: archive.binarySize, countStyle: .file)) · Symbols: \(archive.symbolsAvailable ? "yes" : "no")").font(.caption).foregroundStyle(.secondary)
                if !archive.releaseNotes.isEmpty { Text(archive.releaseNotes).font(.caption) }
            }
            .padding(.vertical, 4)
            .swipeActions {
                Button("Delete", role: .destructive) { coordinator.archives.removeArchive(id: archive.id) }
            }
        }
        .overlay {
            if coordinator.archives.archives.isEmpty {
                ContentUnavailableView("No archives", systemImage: "archivebox", description: Text("Archived builds are recorded here."))
            }
        }
    }

    private var buildHistoryPanel: some View {
        List {
            if !coordinator.builds.buildRecords.isEmpty {
                Button("Clear history", role: .destructive) { coordinator.builds.clearHistory() }
            }
            ForEach(coordinator.builds.buildRecords) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(record.projectName) — \(record.status)").font(.headline)
                    Text("\(record.date, style: .relative) · \(String(format: "%.1fs", record.duration)) · \(record.errors) errors, \(record.warnings) warnings").font(.caption).foregroundStyle(.secondary)
                    Text("\(record.sdk) · \(record.destination) · \(record.configuration) · \(record.compiler)").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .overlay {
            if coordinator.builds.buildRecords.isEmpty {
                ContentUnavailableView("No build history", systemImage: "clock", description: Text("Builds are recorded here when the IDE runs one."))
            }
        }
    }

    private var diagnosticsPanel: some View {
        let errors = coordinator.log.entries.filter { $0.level == .error }
        return List {
            Section("Error log entries (\(errors.count))") {
                if errors.isEmpty {
                    Text("No errors logged.").foregroundStyle(.secondary)
                } else {
                    ForEach(errors.prefix(20)) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.message).font(.headline)
                            Text("\(entry.date, style: .relative) · \(entry.panel)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Build totals") {
                let builds = coordinator.builds.buildRecords
                LabeledContent("Errors across recorded builds", value: "\(builds.reduce(0) { $0 + $1.errors })")
                LabeledContent("Warnings across recorded builds", value: "\(builds.reduce(0) { $0 + $1.warnings })")
            }
        }
    }

    private var dependenciesPanel: some View {
        let deps = packageSwiftDependencies()
        return List {
            if let url = workspaceURL {
                Section("Package.swift — \(url.lastPathComponent)") {
                    if deps.isEmpty {
                        Text("No package dependencies declared in Package.swift.").foregroundStyle(.secondary)
                    } else {
                        ForEach(deps, id: \.self) { dep in Text(dep).font(.system(.body, design: .monospaced)) }
                    }
                }
            } else {
                ContentUnavailableView("No workspace selected", systemImage: "puzzlepiece", description: Text("Open a workspace to list its package dependencies."))
            }
        }
    }

    /// Dependency URLs declared in the workspace's Package.swift, read
    /// textually (the package model in `SwiftCodeIDECore` covers .xcodeproj
    /// references; this panel covers the SwiftPM manifest).
    private func packageSwiftDependencies() -> [String] {
        guard let url = workspaceURL else { return [] }
        let manifest = url.appendingPathComponent("Package.swift")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { return [] }
        var found: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(".package(url:") || trimmed.contains(".package(name:") {
                found.append(trimmed)
            }
        }
        return found
    }

    private var storagePanel: some View {
        let free = workspaceURL.flatMap { OperationsHealth.freeDiskSpace(at: $0) }
        let workspaceSize = workspaceURL.map { OperationsHealth.directorySize(at: $0) } ?? 0
        return List {
            Section("Disk") {
                if let free {
                    LabeledContent("Free space", value: ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
                } else {
                    Text("Free space is unavailable without a workspace.").foregroundStyle(.secondary)
                }
            }
            Section("Workspace") {
                if workspaceURL != nil {
                    LabeledContent("Workspace size (first 2,000 files)", value: ByteCountFormatter.string(fromByteCount: workspaceSize, countStyle: .file))
                } else {
                    Text("Open a workspace to measure its size.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var securityPanel: some View {
        List {
            Section("Committed-secret scan") {
                if let url = workspaceURL {
                    Button(securityScanned ? "Rescan workspace" : "Scan workspace") {
                        securityFindings = OperationsSecurity.scan(root: url)
                        securityScanned = true
                    }
                    if securityScanned {
                        if securityFindings.isEmpty {
                            Text("No secret patterns found in the first 500 scanned files.").foregroundStyle(.secondary)
                        } else {
                            ForEach(securityFindings) { finding in
                                VStack(alignment: .leading) {
                                    Text("\(finding.file):\(finding.line)").font(.headline)
                                    Text(finding.pattern).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Text("Open a workspace to scan it for committed secrets.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var aiReportsPanel: some View {
        List {
            Section("Local report") {
                Button("Generate report") { aiReport = localReport() }
                if let aiReport {
                    Text(aiReport).font(.caption).textSelection(.enabled)
                } else {
                    Text("Computed locally from recorded builds, archives and the registry — no model call is made.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func localReport() -> String {
        let builds = coordinator.builds.buildRecords
        let lines = [
            "Operations report",
            "Projects registered: \(coordinator.registryEntries.count)",
            "Builds recorded: \(builds.count)",
            "Build success rate: \(builds.isEmpty ? "n/a" : "\(Int(coordinator.builds.successRate * 100))%")",
            "Total build errors: \(builds.reduce(0) { $0 + $1.errors })",
            "Total build warnings: \(builds.reduce(0) { $0 + $1.warnings })",
            "Archives: \(coordinator.archives.archives.count)",
            "Unread notifications: \(coordinator.notifications.unreadCount)",
        ]
        return lines.joined(separator: "\n")
    }

    private var healthPanel: some View {
        let factors = OperationsHealth.factors(workspaceURL: workspaceURL, buildHistory: coordinator.builds, registryCount: coordinator.registryEntries.count)
        return List(factors) { factor in
            HStack {
                Image(systemName: factor.healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(factor.healthy ? .green : .red)
                VStack(alignment: .leading) {
                    Text(factor.name).font(.headline)
                    Text(factor.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var logsPanel: some View {
        List(coordinator.log.entries) { entry in
            VStack(alignment: .leading) {
                Text(entry.message).font(.headline)
                Text("\(entry.date, style: .relative) · \(entry.panel) · \(entry.level.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .overlay {
            if coordinator.log.entries.isEmpty {
                ContentUnavailableView("No log entries", systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    private var timelinePanel: some View {
        let builds = coordinator.builds.buildRecords.map { (date: $0.date, title: "Build: \($0.projectName) — \($0.status)") }
        let archives = coordinator.archives.archives.map { (date: $0.date, title: "Archive: \($0.projectName) \($0.version)") }
        let notes = coordinator.notifications.notifications.map { (date: $0.date, title: $0.title) }
        let items = (builds + archives + notes).sorted { $0.date > $1.date }
        return List(items, id: \.title) { item in
            VStack(alignment: .leading) {
                Text(item.title).font(.headline)
                Text(item.date, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing on the timeline yet", systemImage: "calendar.day.timeline.left")
            }
        }
    }

    private struct OperationsSearchHit: Identifiable {
        var id: String { kind + ":" + title }
        let kind: String
        let title: String
    }

    private var searchPanel: some View {
        let query = coordinator.searchQuery.lowercased()
        var hits: [OperationsSearchHit] = coordinator.registryEntries
            .filter { query.isEmpty || $0.name.lowercased().contains(query) }
            .map { OperationsSearchHit(kind: "Project", title: $0.name) }
        hits += coordinator.builds.buildRecords
            .filter { query.isEmpty || $0.projectName.lowercased().contains(query) }
            .map { OperationsSearchHit(kind: "Build", title: "\($0.projectName) — \($0.status)") }
        return List {
            TextField("Search projects and builds", text: $coordinator.searchQuery)
                .textFieldStyle(.roundedBorder)
            ForEach(hits) { hit in
                HStack {
                    Text(hit.title)
                    Spacer()
                    Text(hit.kind).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var queuePanel: some View {
        List(coordinator.queue.operations) { op in
            HStack {
                Text(op.name).font(.headline)
                Spacer()
                Text(op.status.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            if let error = op.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .overlay {
            if coordinator.queue.operations.isEmpty {
                ContentUnavailableView("Queue is empty", systemImage: "list.bullet.rectangle")
            }
        }
    }

    private var notificationsPanel: some View {
        List(coordinator.notifications.notifications) { note in
            HStack {
                VStack(alignment: .leading) {
                    Text(note.title).font(.headline)
                    Text(note.subtitle).font(.caption).foregroundStyle(.secondary)
                    Text("\(note.date, style: .relative) · \(note.type)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if !note.isRead {
                    Button("Mark read") { coordinator.notifications.markRead(id: note.id) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .overlay {
            if coordinator.notifications.notifications.isEmpty {
                ContentUnavailableView("No notifications", systemImage: "bell")
            }
        }
    }

    private var preferencesPanel: some View {
        List {
            Section("Stores") {
                Text("Operations data lives in Application Support/SwiftCode/Operations (build_history.json, archives.json, notifications.json, operations_log.json).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Danger zone") {
                Button("Clear build history", role: .destructive) { coordinator.builds.clearHistory() }
            }
            Section("IDE settings") {
                Text("Editor, appearance and account settings live in Settings, not in Operations.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
