import AppKit
import Foundation
import SwiftUI
import SwiftCodeAssistant
import SwiftCodeGitHub

@MainActor
public final class CIWindowManager: NSObject {
    public static let shared = CIWindowManager()
    private var controllers: [String: CIWindowController] = [:]

    private override init() {}

    public func showWindow(workspaceFolder: URL, service: GitHubActionsService? = nil) {
        let key = workspaceFolder.standardizedFileURL.path
        if let existing = controllers[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = CIWindowController(workspaceFolder: workspaceFolder, service: service)
        controllers[key] = controller
        controller.window?.delegate = self
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow(workspaceFolder: URL) {
        controllers[workspaceFolder.standardizedFileURL.path]?.close()
    }

    func controllerClosed(_ controller: CIWindowController) {
        controllers[controller.workspaceFolder.standardizedFileURL.path] = nil
    }
}

extension CIWindowManager: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let wc = controllers.values.first(where: { $0.window === window }) else { return }
        controllerClosed(wc)
    }
}

@MainActor
public final class CIWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public static let size = NSSize(width: 1100, height: 700)
    static let repositoryDefaultsKey = "com.swiftcode.ci.repository"

    public let workspaceFolder: URL
    public let service: GitHubActionsService

    private let ownerField = NSTextField()
    private let repoField = NSTextField()
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let rerunButton = NSButton(title: "Re-run", target: nil, action: nil)
    private let createButton = NSButton(title: "Create Visual Workflow", target: nil, action: nil)
    private let editButton = NSButton(title: "Edit Workflow", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let runsTable = NSTableView()
    private let jobsTextView = NSTextView()
    private let logsTextView = NSTextView()
    private let logsButton = NSButton(title: "Logs", target: nil, action: nil)

    private var runs: [GitHubWorkflowRun] = []
    private var selectedRun: GitHubWorkflowRun?
    private var jobs: [GitHubWorkflowJob] = []
    private var selectedJob: GitHubWorkflowJob?
    private var isLoading = false

    public init(workspaceFolder: URL, service: GitHubActionsService? = nil) {
        self.workspaceFolder = workspaceFolder
        self.service = service ?? GitHubActionsService(store: defaultSecretStore())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CI / Visual Workflows — \(workspaceFolder.lastPathComponent)"
        window.minSize = NSSize(width: 900, height: 550)
        window.setFrameAutosaveName("SwiftCodeCIWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        loadRepository()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func loadRepository() {
        if let remote = GitPushClient.live(store: service.store).remoteURL(workspaceFolder),
           let parsed = GitHubRepoReference.parseRemoteURL(remote) {
            ownerField.stringValue = parsed.owner
            repoField.stringValue = parsed.repo
            return
        }
        if let saved = UserDefaults.standard.string(forKey: Self.repositoryDefaultsKey),
           let parsed = GitHubRepoReference.parse(saved) {
            ownerField.stringValue = parsed.owner
            repoField.stringValue = parsed.repo
        }
    }

    private func build() {
        guard let contentView = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        ownerField.placeholderString = "owner"
        ownerField.translatesAutoresizingMaskIntoConstraints = false
        ownerField.widthAnchor.constraint(equalToConstant: 180).isActive = true
        repoField.placeholderString = "repo"
        repoField.translatesAutoresizingMaskIntoConstraints = false
        repoField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        rerunButton.target = self
        rerunButton.action = #selector(rerunClicked)
        rerunButton.isEnabled = false
        createButton.target = self
        createButton.action = #selector(createVisualWorkflowClicked)
        editButton.target = self
        editButton.action = #selector(editWorkflowClicked)
        updateEditButton()
        let repoRow = NSStackView(views: [
            NSTextField(labelWithString: "Repository:"), ownerField,
            NSTextField(labelWithString: "/"), repoField,
            refreshButton, rerunButton, createButton, editButton,
        ])
        repoRow.orientation = .horizontal
        repoRow.spacing = 8
        repoRow.alignment = .centerY
        stack.addArrangedSubview(repoRow)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusLabel)

        let columns: [(String, String, CGFloat)] = [
            ("run", "Run", 260), ("branch", "Branch", 160),
            ("status", "Status", 120), ("conclusion", "Result", 120),
            ("event", "Event", 120),
        ]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            runsTable.addTableColumn(column)
        }
        runsTable.dataSource = self
        runsTable.delegate = self
        runsTable.target = self
        runsTable.doubleAction = #selector(runDoubleClicked)
        let runsScroll = NSScrollView()
        runsScroll.documentView = runsTable
        runsScroll.hasVerticalScroller = true
        runsScroll.translatesAutoresizingMaskIntoConstraints = false
        runsScroll.heightAnchor.constraint(equalToConstant: 240).isActive = true
        stack.addArrangedSubview(runsScroll)

        jobsTextView.isEditable = false
        jobsTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let jobsScroll = NSScrollView()
        jobsScroll.documentView = jobsTextView
        jobsScroll.hasVerticalScroller = true
        jobsScroll.translatesAutoresizingMaskIntoConstraints = false
        jobsScroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        stack.addArrangedSubview(jobsScroll)

        logsButton.target = self
        logsButton.action = #selector(logsClicked)
        logsButton.isEnabled = false
        stack.addArrangedSubview(logsButton)

        logsTextView.isEditable = false
        logsTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let logsScroll = NSScrollView()
        logsScroll.documentView = logsTextView
        logsScroll.hasVerticalScroller = true
        logsScroll.translatesAutoresizingMaskIntoConstraints = false
        logsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        stack.addArrangedSubview(logsScroll)
    }

    @objc private func refreshClicked() { refresh() }

    @objc private func createVisualWorkflowClicked() {
        guard let window else { return }
        let sheet = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 860, height: 640)),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        sheet.title = "Create Visual Workflow"
        sheet.contentViewController = NSHostingController(
            rootView: WorkflowsCreateView(projectRoot: workspaceFolder)
        )
        window.beginSheet(sheet) { [weak self] _ in self?.updateEditButton() }
    }

    private var workflowFileURL: URL {
        workspaceFolder.appendingPathComponent(".github/workflows/workflow.yml")
    }

    private func updateEditButton() {
        editButton.isEnabled = FileManager.default.fileExists(atPath: workflowFileURL.path)
    }

    @objc private func editWorkflowClicked() {
        guard let window else { return }
        guard let content = try? String(contentsOf: workflowFileURL, encoding: .utf8) else {
            updateEditButton()
            return
        }
        let state = WorkflowEditorContent(content)
        let sheet = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 860, height: 640)),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        sheet.title = "Edit Workflow — workflow.yml"
        sheet.contentViewController = NSHostingController(
            rootView: WorkflowEditorView(content: state.$text, fileName: "workflow.yml") { [weak self] newContent in
                guard let self else { return }
                do {
                    try newContent.write(to: self.workflowFileURL, atomically: true, encoding: .utf8)
                    window.endSheet(sheet)
                } catch {
                }
            }
        )
        window.beginSheet(sheet)
    }

    func refresh() {
        let owner = ownerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = repoField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repo.isEmpty, !isLoading else { return }
        UserDefaults.standard.set("\(owner)/\(repo)", forKey: Self.repositoryDefaultsKey)
        isLoading = true
        statusLabel.stringValue = "Loading runs for \(owner)/\(repo)..."
        let service = service
        Task {
            do {
                let runs = try await service.listRuns(owner: owner, repo: repo)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    self.runs = runs
                    self.selectedRun = nil
                    self.jobs = []
                    self.jobsTextView.string = ""
                    self.runsTable.reloadData()
                    self.rerunButton.isEnabled = false
                    self.logsButton.isEnabled = false
                    self.statusLabel.stringValue = runs.isEmpty
                        ? "No workflow runs for \(owner)/\(repo) yet."
                        : "\(runs.count) run\(runs.count == 1 ? "" : "s") for \(owner)/\(repo)."
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    self.statusLabel.stringValue = "Could not load runs: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func rerunClicked() {
        guard let run = selectedRun else { return }
        let owner = ownerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = repoField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = service
        Task {
            do {
                try await service.rerun(owner: owner, repo: repo, runID: run.id)
                await MainActor.run { [weak self] in
                    self?.statusLabel.stringValue = "Re-run requested for run \(run.id)."
                    self?.refresh()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.statusLabel.stringValue = "Could not re-run: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func logsClicked() {
        guard let job = selectedJob else { return }
        let owner = ownerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = repoField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = service
        logsTextView.string = "Fetching logs for \(job.name ?? "job")..."
        Task {
            do {
                let logs = try await service.jobLogs(owner: owner, repo: repo, jobID: job.id)
                await MainActor.run { [weak self] in
                    self?.logsTextView.string = logs.isEmpty ? "No logs returned for this job." : logs
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.logsTextView.string = "Failed to fetch logs: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func runDoubleClicked() {
        guard runsTable.clickedRow >= 0, runs.indices.contains(runsTable.clickedRow) else { return }
        selectRun(runs[runsTable.clickedRow])
    }

    private func selectRun(_ run: GitHubWorkflowRun) {
        selectedRun = run
        rerunButton.isEnabled = true
        let owner = ownerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = repoField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = service
        jobsTextView.string = "Loading jobs for run \(run.id)..."
        Task {
            do {
                let jobs = try await service.listJobs(owner: owner, repo: repo, runID: run.id)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.jobs = jobs
                    self.selectedJob = jobs.first
                    self.logsButton.isEnabled = self.selectedJob != nil
                    self.jobsTextView.string = jobs.isEmpty
                        ? "No jobs executed for this run."
                        : jobs.map { job in
                            var lines = ["\(job.conclusion == "success" ? "✓" : job.status == "in_progress" ? "…": "•") \(job.name ?? "job") — \(job.status ?? "") / \(job.conclusion ?? "")"]
                            for step in job.steps ?? [] {
                                lines.append("    \(step.conclusion == "success" ? "✓" : "•") \(step.name ?? "step") (\(step.status ?? ""))")
                            }
                            return lines.joined(separator: "\n")
                        }.joined(separator: "\n\n")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.jobsTextView.string = "Failed to load jobs: \(error.localizedDescription)"
                }
            }
        }
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { runs.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard runs.indices.contains(row) else { return nil }
        let run = runs[row]
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "run": value = run.name ?? "Run \(run.id)"
        case "branch": value = run.headBranch ?? ""
        case "status": value = run.status ?? ""
        case "conclusion": value = run.conclusion ?? ""
        case "event": value = run.event ?? ""
        default: value = ""
        }
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        cell.textField = field
        cell.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = runsTable.selectedRow
        guard row >= 0, runs.indices.contains(row) else { return }
        selectRun(runs[row])
    }
}

private final class WorkflowEditorContent: ObservableObject {
    @Published var text: String
    init(_ text: String) { self.text = text }
}
