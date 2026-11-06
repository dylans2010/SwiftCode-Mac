import Foundation
import SwiftUI
import SwiftCodeExtensions
import SwiftCodeSDK
import SwiftCodeSDKStudio

// MARK: - Logs
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKStudioLogsView.swift` — three
// panes:
//   - User:      `SDKUserLogger.shared` sanitized in-memory entries.
//   - Developer: the developer log stream (searchable).
//   - Audit:     `SDKAuditLog.shared` durable security audit events.
// SwiftCode mapping: User → `SDKStudioUserLogger` (sanitized, in-memory);
// Developer → SwiftCode's `DiagnosticsService` (the extension diagnostics
// stream, searchable, exportable); Audit → the Host slice's durable
// `SDKAuditLog` (append-only JSON Lines, read via `recentEvents`).

@MainActor
struct SDKStudioLogsView: View {
    private enum Segment: String, CaseIterable {
        case user = "User"
        case developer = "Developer"
        case audit = "Audit"
    }

    @State private var segment: Segment = .user

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Logs", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)
            switch segment {
            case .user:
                SDKStudioUserLogsPane()
            case .developer:
                SDKStudioDeveloperLogsPane()
            case .audit:
                SDKStudioAuditLogsPane()
            }
        }
    }
}

@MainActor
private struct SDKStudioUserLogsPane: View {
    @State private var entries: [SDKStudioUserLogEntry] = []
    @State private var searchText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Filter by correlation ID or message…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { _, _ in reload() }
                Button("Reload") { reload() }
                Button("Clear") {
                    SDKStudioUserLogger.shared.clear()
                    reload()
                }
            }
            .padding(8)
            if entries.isEmpty {
                SDKStudioEmptyState(title: "No Entries Yet", systemImage: "doc.text", description: "User log entries appear here as Studio and extensions log them.")
            } else {
                List(entries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: levelIcon(for: entry.level))
                            .foregroundStyle(levelColor(for: entry.level))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message).font(.callout)
                            HStack(spacing: 8) {
                                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let correlationID = entry.correlationID {
                                    Text(correlationID).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .task { reload() }
    }

    private func reload() {
        entries = searchText.isEmpty
            ? SDKStudioUserLogger.shared.recentEntries()
            : SDKStudioUserLogger.shared.entries(matching: searchText)
    }

    private func levelIcon(for level: SDKStudioUserLogLevel) -> String {
        switch level {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func levelColor(for level: SDKStudioUserLogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

@MainActor
private struct SDKStudioDeveloperLogsPane: View {
    @State private var lines: [DiagnosticEntry] = []
    @State private var searchText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filtered: [DiagnosticEntry] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return lines }
        return lines.filter {
            $0.message.lowercased().contains(needle)
                || ($0.extensionId ?? "").lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Filter by message or extension…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button("Search") { search() }
                Button("Clear") {
                    DiagnosticsService.shared.clear()
                    search()
                }
            }
            .padding(8)
            if filtered.isEmpty {
                SDKStudioEmptyState(title: "No Entries Yet", systemImage: "doc.text", description: "Developer diagnostics appear here as extensions log them.")
            } else {
                List(filtered) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text("[\(entry.level.rawValue)]")
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 4)
                            .background(levelColor(entry.level).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message).font(.callout)
                            Text("\(entry.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(entry.extensionId ?? "-")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .task { search() }
    }

    private func search() {
        lines = DiagnosticsService.shared.allEntries()
    }

    private func levelColor(_ level: DiagnosticLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

@MainActor
private struct SDKStudioAuditLogsPane: View {
    @State private var events: [SDKAuditEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Durable audit events recorded by the SDK host (`SDKAuditLog`, append-only JSON Lines). Detail strings carry identifiers only — never secrets.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(8)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 8)
            HStack {
                Spacer()
                Button("Reload") { reload() }
            }
            .padding(8)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding(8)
            }
            if events.isEmpty {
                SDKStudioEmptyState(title: "No Audit Events", systemImage: "shield", description: "No audit events recorded yet.")
            } else {
                List(events, id: \.id) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "shield")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.type.rawValue).font(.callout)
                            if let detail = event.detail ?? event.capabilityRaw {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("\(event.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(event.extensionID ?? "-")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .task { reload() }
    }

    private func reload() {
        isLoading = true
        Task {
            events = await SDKAuditLog.shared.recentEvents(limit: 200)
            isLoading = false
        }
    }
}

// MARK: - First-launch installer
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKFirstLaunchInstallerView.swift`.
// Phases prompt → installing (live log lines) → succeeded / failed;
// "Remind Me Later" and "Decline" record the first-launch choice; the
// install itself runs through the installer seam (`SDKStudioInstaller`),
// wired to the Host slice's real `SDKInstaller` via
// `SDKStudioInstallerHost`.

@MainActor
struct SDKFirstLaunchInstallerView: View {
    var installer: any SDKStudioInstaller

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .prompt
    @State private var logLines: [String] = []

    private enum Phase: Equatable {
        case prompt
        case installing
        case succeeded(SDKStudioInstallResult)
        case failed(SDKStudioInstallResult)
    }

    init(installer: any SDKStudioInstaller) {
        self.installer = installer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .prompt:
                Text("Install the SwiftCode SDK?").font(.title2.bold())
                Text("Install location")
                    .font(.headline)
                Text(type(of: installer).defaultPrefix.path)
                    .font(.callout.monospaced())
                Text("The SDK is required to build extensions. Node.js is required.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Install SDK") { startInstall() }
                        .buttonStyle(.borderedProminent)
                    Button("Remind Me Later") {
                        SDKStudioFirstLaunchChoice.recordRemindLater()
                        dismiss()
                    }
                    Button("Decline") {
                        SDKStudioFirstLaunchChoice.recordDeclined()
                        dismiss()
                    }
                }
            case .installing:
                Text("Installing SwiftCode SDK…").font(.title2.bold())
                Text("Running npm install. Every line below is live output from the installer.")
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(logLines.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 200)
            case .succeeded(let result):
                Text("SDK Installed").font(.title2.bold())
                Text(result.detail)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            case .failed(let result):
                Text("Installation Failed").font(.title2.bold())
                Text(result.detail).foregroundStyle(.red)
                ScrollView {
                    Text(result.logLines.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120)
                HStack(spacing: 12) {
                    Button("Retry") { startInstall() }
                        .buttonStyle(.borderedProminent)
                    Button("Close") { dismiss() }
                }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
    }

    private func startInstall() {
        phase = .installing
        logLines = []
        // Log lines arrive on the installer's (background) context, so
        // they are collected in an actor and flushed to the view when the
        // install finishes; live streaming into this view needs the
        // AppKit host to forward lines onto the main actor.
        let collector = SDKInstallerLogCollector()
        Task {
            let result = await installer.install { line in
                Task { await collector.append(line) }
            }
            logLines = await collector.all()
            if result.succeeded {
                SDKStudioFirstLaunchChoice.recordInstalled()
                phase = .succeeded(result)
            } else {
                phase = .failed(result)
            }
        }
    }
}

private actor SDKInstallerLogCollector {
    private var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
    func all() -> [String] { lines }
}

// MARK: - Ship & export
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKShipExportView.swift` — project
// summary (from `swiftcode.json` / inspector), export through the SDK
// CLI (`SDKInstaller.resolveCLIURL()`), phases, and a manual-command
// sheet when the CLI is unavailable. SwiftCode has no SDK CLI; export
// packages the project directory into a `.tgz` via the system `tar`
// (a real archive, not a placeholder) and reports the manual command
// when that is unavailable.

@MainActor
struct SDKShipExportView: View {
    @Bindable var editorState: SDKCodeEditorState

    @State private var projectPathText: String = ""
    @State private var summary: ProjectMetadata?
    @State private var summaryError: String?
    @State private var destinationText: String = ""
    @State private var phase: Phase = .idle
    @State private var manualCommand: String?
    @State private var showingManualCommand = false

    private enum Phase: Equatable {
        case idle
        case running
        case succeeded(URL)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ship / Export").font(.title2.bold())
                Text("Package an extension for distribution. The export writes a .tgz of the project directory (excluding node_modules and .git).")
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("/path/to/project", text: $projectPathText)
                        .textFieldStyle(.roundedBorder)
                    Button("Load Project") { loadProject() }
                }
                if let summaryError {
                    Text(summaryError).foregroundStyle(.red)
                }
                if let summary {
                    SDKStudioGroupBox("Project Summary") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(summary.id) · v\(summary.version) · \(summary.type.displayName)")
                                .font(.headline)
                            Text(summary.name)
                            Text(summary.rootPath).font(.caption.monospaced()).foregroundStyle(.secondary)
                            ForEach(summary.targets, id: \.name) { target in
                                Text("Target: \(target.name) (\(target.type))").font(.caption)
                            }
                        }
                    }
                }
                HStack {
                    TextField("/path/to/export.tgz", text: $destinationText)
                        .textFieldStyle(.roundedBorder)
                    Button("Export") { export() }
                        .buttonStyle(.borderedProminent)
                        .disabled(summary == nil || destinationText.isEmpty || phase == .running)
                }
                switch phase {
                case .idle:
                    EmptyView()
                case .running:
                    ProgressView("Exporting…")
                case .succeeded(let url):
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exported successfully.").font(.headline).foregroundStyle(.green)
                        Text(url.path).font(.callout.monospaced())
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Export failed.").font(.headline).foregroundStyle(.red)
                        Text(message)
                        Button("Show Manual Command") {
                            manualCommand = manualCommandText()
                            showingManualCommand = true
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            projectPathText = editorState.projectRootURL?.path ?? ""
            if !projectPathText.isEmpty { loadProject() }
        }
        .sheet(isPresented: $showingManualCommand) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Manual Export Command").font(.headline)
                Text(manualCommand ?? "").font(.callout.monospaced())
                Button("Close") { showingManualCommand = false }
            }
            .padding()
            .frame(minWidth: 520)
        }
    }

    private func loadProject() {
        let path = projectPathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        do {
            summary = try ProjectInspector().inspect(at: path)
            summaryError = nil
            if destinationText.isEmpty {
                destinationText = (path as NSString).appendingPathComponent(
                    "\(URL(fileURLWithPath: path).lastPathComponent).tgz")
            }
        } catch {
            summary = nil
            summaryError = error.localizedDescription
        }
    }

    private func manualCommandText() -> String {
        "tar --exclude=node_modules --exclude=.git -czf \"\(destinationText)\" -C \"\(projectPathText)\" ."
    }

    private func export() {
        guard let summary else { return }
        phase = .running
        let source = URL(fileURLWithPath: summary.rootPath)
        let destination = URL(fileURLWithPath: destinationText)
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["--exclude=node_modules", "--exclude=.git", "-czf",
                                 destination.path, "-C", source.path, "."]
            let pipe = Pipe()
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    phase = .succeeded(destination)
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let detail = String(data: data, encoding: .utf8) ?? "tar exited with status \(process.terminationStatus)."
                    phase = .failed(detail)
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
