import AppKit
import Foundation

// MARK: - Sandboxed terminal window (gap closure)
//
// The `sandbox.view` window (specs/ide/gap-closure-windows-
// artboards.md §8): a command field + output view over
// `SandboxedCommandRunner`. One command per run, one session per
// window, user-opened only — there is no SDK view and no MCP
// tool for it. This is not a shell: no `;`, `|`, `$()`, backticks
// or any other shell syntax is ever interpreted, the command must
// be on the allowlist, the working directory stays inside the
// workspace, and the environment is scrubbed. The policy note at
// the bottom of the window says exactly that.

/// The sandboxed terminal's window manager: one shared window per
/// workspace folder, raised when already open.
@MainActor
public final class SandboxTerminalWindowManager: NSObject {
    public static let shared = SandboxTerminalWindowManager()
    private var controllers: [String: SandboxTerminalWindowController] = [:]

    private override init() {}

    public func showWindow(workspaceFolder: URL) {
        let key = workspaceFolder.standardizedFileURL.path
        if let existing = controllers[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = SandboxTerminalWindowController(workspaceFolder: workspaceFolder)
        controllers[key] = controller
        controller.window?.delegate = self
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow(workspaceFolder: URL) {
        controllers[workspaceFolder.standardizedFileURL.path]?.close()
    }

    func controllerClosed(_ controller: SandboxTerminalWindowController) {
        controllers[controller.workspaceFolder.standardizedFileURL.path] = nil
    }
}

extension SandboxTerminalWindowManager: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let wc = controllers.values.first(where: { $0.window === window }) else { return }
        controllerClosed(wc)
    }
}

@MainActor
public final class SandboxTerminalWindowController: NSWindowController, NSTextFieldDelegate {
    public static let size = NSSize(width: 900, height: 600)

    public let workspaceFolder: URL
    public var policy: SandboxPolicy

    private let commandField = NSTextField()
    private let runButton = NSButton(title: "Run", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let cwdLabel = NSTextField(labelWithString: "")
    private let outputTextView = NSTextView()
    private var currentTask: Task<Void, Never>?
    private var isRunning = false

    public init(workspaceFolder: URL, policy: SandboxPolicy = .load()) {
        self.workspaceFolder = workspaceFolder
        self.policy = policy
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sandboxed Terminal — \(workspaceFolder.lastPathComponent)"
        window.minSize = NSSize(width: 700, height: 420)
        window.setFrameAutosaveName("SwiftCodeSandboxTerminalWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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

        cwdLabel.font = .systemFont(ofSize: 11)
        cwdLabel.textColor = .secondaryLabelColor
        cwdLabel.stringValue = "Working directory: \(workspaceFolder.path)"
        stack.addArrangedSubview(cwdLabel)

        commandField.placeholderString = "Command (e.g. git status) — one command, no shell syntax"
        commandField.delegate = self
        commandField.target = self
        commandField.action = #selector(runClicked)
        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.widthAnchor.constraint(equalToConstant: 560).isActive = true
        runButton.target = self
        runButton.action = #selector(runClicked)
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        stopButton.isEnabled = false
        let commandRow = NSStackView(views: [commandField, runButton, stopButton])
        commandRow.orientation = .horizontal
        commandRow.spacing = 8
        commandRow.alignment = .centerY
        stack.addArrangedSubview(commandRow)

        outputTextView.isEditable = false
        outputTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let outputScroll = NSScrollView()
        outputScroll.documentView = outputTextView
        outputScroll.hasVerticalScroller = true
        outputScroll.translatesAutoresizingMaskIntoConstraints = false
        outputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        stack.addArrangedSubview(outputScroll)

        let policyNote = NSTextField(labelWithString: "Sandboxed: one allowlisted command at a time (\(policy.allowedCommands.joined(separator: ", "))); git is read-only (status, log, diff, branch, remote, rev-parse, show, ls-files). Shell syntax (; | $() `) is rejected, the working directory stays inside the workspace, the environment is scrubbed, and output is capped. This is not a macOS Seatbelt sandbox — see the spec.")
        policyNote.font = .systemFont(ofSize: 11)
        policyNote.textColor = .secondaryLabelColor
        policyNote.lineBreakMode = .byWordWrapping
        policyNote.translatesAutoresizingMaskIntoConstraints = false
        policyNote.widthAnchor.constraint(equalToConstant: 820).isActive = true
        stack.addArrangedSubview(policyNote)
    }

    @objc private func runClicked() {
        let commandLine = commandField.stringValue
        guard !commandLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isRunning else { return }
        isRunning = true
        runButton.isEnabled = false
        stopButton.isEnabled = true
        appendLine("$ \(commandLine)")
        let folder = workspaceFolder
        let policy = policy
        currentTask = Task {
            do {
                let result = try await SandboxedCommandRunner.run(
                    commandLine: commandLine, workingDirectory: folder, workspaceRoot: folder,
                    policy: policy) { [weak self] line in
                        Task { @MainActor in self?.appendLine(line) }
                    }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.finishRun()
                    if result.truncated {
                        self.appendLine("(output truncated at the sandbox cap)")
                    }
                    self.appendLine("exit \(result.exitCode)")
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.finishRun()
                    self.appendLine("error: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func stopClicked() {
        currentTask?.cancel()
        currentTask = nil
        finishRun()
        appendLine("(stopped)")
    }

    private func finishRun() {
        isRunning = false
        runButton.isEnabled = true
        stopButton.isEnabled = false
        currentTask = nil
    }

    func appendLine(_ line: String) {
        let text = outputTextView.string
        outputTextView.string = text.isEmpty ? line : text + "\n" + line
        outputTextView.scrollToEndOfDocument(nil)
    }
}
