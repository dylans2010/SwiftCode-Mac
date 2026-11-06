import AppKit
import Foundation
import YcodeAssistant

// MARK: - Deployments window (gap closure)
//
// The `deployConsole.view` window (specs/ide/gap-closure-windows-
// artboards.md §5): platform picker (Netlify / Vercel / GitHub
// Pages), custom-domain toggle, per-provider token storage in the
// secret store, Deploy, logs, and the result URL. Legacy's
// `DeploymentsView` shape, rebuilt in Ycode style — no orange
// accents, no Legacy chrome.
//
// The window states plainly, next to Deploy, that Netlify/Vercel
// build from their GitHub integration after the push; the returned
// URL is the dashboard (or the custom domain), never a fabricated
// site URL.

/// The Deployments window manager: one shared window per workspace
/// folder, raised when already open.
@MainActor
public final class DeploymentWindowManager: NSObject {
    public static let shared = DeploymentWindowManager()
    private var controllers: [String: DeploymentWindowController] = [:]

    private override init() {}

    public func showWindow(workspaceFolder: URL, service: DeploymentService? = nil) {
        let key = workspaceFolder.standardizedFileURL.path
        if let existing = controllers[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = DeploymentWindowController(workspaceFolder: workspaceFolder, service: service)
        controllers[key] = controller
        controller.window?.delegate = self
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow(workspaceFolder: URL) {
        controllers[workspaceFolder.standardizedFileURL.path]?.close()
    }

    func controllerClosed(_ controller: DeploymentWindowController) {
        controllers[controller.workspaceFolder.standardizedFileURL.path] = nil
    }
}

extension DeploymentWindowManager: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard let controller = notification.object as? NSWindow,
              let wc = controllers.values.first(where: { $0.window === controller }) else { return }
        controllerClosed(wc)
    }
}

@MainActor
public final class DeploymentWindowController: NSWindowController {
    public static let size = NSSize(width: 900, height: 640)

    public let workspaceFolder: URL
    /// The service under test (tests inject a stub session + git).
    public let service: DeploymentService

    private var platform: DeploymentPlatform = .netlify
    private var isDeploying = false

    private let platformControl = NSSegmentedControl()
    private let domainCheck = NSButton(checkboxWithTitle: "Use Custom Domain", target: nil, action: nil)
    private let domainField = NSTextField()
    private let tokenStatusLabel = NSTextField(labelWithString: "")
    private let tokenField = NSSecureTextField()
    private let saveTokenButton = NSButton(title: "Save Token", target: nil, action: nil)
    private let deployButton = NSButton(title: "Start Deployment", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let logTextView = NSTextView()
    private let resultLabel = NSTextField(labelWithString: "")
    private let openBrowserButton = NSButton(title: "Open In Browser", target: nil, action: nil)
    private var resultURL: URL?

    public init(workspaceFolder: URL, service: DeploymentService? = nil) {
        self.workspaceFolder = workspaceFolder
        self.service = service ?? DeploymentService(store: defaultSecretStore())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Deployments — \(workspaceFolder.lastPathComponent)"
        window.minSize = NSSize(width: 700, height: 480)
        window.setFrameAutosaveName("YcodeDeploymentWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        refreshTokenStatus()
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

        platformControl.segmentCount = 3
        for (i, platform) in DeploymentPlatform.allCases.enumerated() {
            platformControl.setLabel(platform.rawValue, forSegment: i)
        }
        platformControl.selectedSegment = 0
        platformControl.target = self
        platformControl.action = #selector(platformChanged)
        stack.addArrangedSubview(labeledRow("Deployment Platform:", platformControl))

        domainCheck.target = self
        domainCheck.action = #selector(domainCheckChanged)
        stack.addArrangedSubview(domainCheck)
        domainField.placeholderString = "example.com"
        domainField.isEnabled = false
        domainField.translatesAutoresizingMaskIntoConstraints = false
        domainField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.addArrangedSubview(labeledRow("Custom Domain:", domainField))

        tokenStatusLabel.font = .systemFont(ofSize: 11)
        tokenStatusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(labeledRow("Token:", tokenStatusLabel))
        tokenField.placeholderString = "Paste the \(platform.rawValue) token — stored in the keychain, never shown again"
        tokenField.translatesAutoresizingMaskIntoConstraints = false
        tokenField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        saveTokenButton.target = self
        saveTokenButton.action = #selector(saveToken)
        let tokenRow = NSStackView(views: [tokenField, saveTokenButton])
        tokenRow.orientation = .horizontal
        tokenRow.spacing = 8
        stack.addArrangedSubview(labeledRow("", tokenRow))

        deployButton.bezelStyle = .rounded
        deployButton.target = self
        deployButton.action = #selector(deployClicked)
        stack.addArrangedSubview(deployButton)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Netlify and Vercel build from their GitHub integration after the push; the result links to the provider dashboard."
        statusLabel.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(statusLabel)

        logTextView.isEditable = false
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let logScroll = NSScrollView()
        logScroll.documentView = logTextView
        logScroll.hasVerticalScroller = true
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        stack.addArrangedSubview(logScroll)

        resultLabel.font = .systemFont(ofSize: 12)
        resultLabel.isSelectable = true
        resultLabel.lineBreakMode = .byTruncatingMiddle
        resultLabel.isHidden = true
        stack.addArrangedSubview(resultLabel)
        openBrowserButton.target = self
        openBrowserButton.action = #selector(openInBrowser)
        openBrowserButton.isHidden = true
        stack.addArrangedSubview(openBrowserButton)
    }

    private func labeledRow(_ label: String, _ view: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        if !label.isEmpty {
            let field = NSTextField(labelWithString: label)
            field.font = .systemFont(ofSize: 12)
            row.addArrangedSubview(field)
        }
        row.addArrangedSubview(view)
        return row
    }

    // MARK: - Token

    func refreshTokenStatus() {
        let stored = service.token(for: platform) != nil
        tokenStatusLabel.stringValue = stored
            ? "\(platform.rawValue) token: Stored"
            : "\(platform.rawValue) token: Not stored — deployment is disabled until one is saved."
        tokenField.placeholderString = "Paste the \(platform.rawValue) token — stored in the keychain, never shown again"
        deployButton.isEnabled = stored && !isDeploying
    }

    @objc private func saveToken() {
        let value = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { NSSound.beep(); return }
        do {
            try service.store.write(Data(value.utf8), for: platform.tokenAccount)
            tokenField.stringValue = ""
            appendLog("\(platform.rawValue) token saved to the keychain.")
            refreshTokenStatus()
        } catch {
            appendLog("Could not save the token: \(error.localizedDescription)")
        }
    }

    // MARK: - Deploy

    @objc private func platformChanged() {
        platform = DeploymentPlatform.allCases[platformControl.selectedSegment]
        refreshTokenStatus()
    }

    @objc private func domainCheckChanged() {
        domainField.isEnabled = domainCheck.state == .on
    }

    @objc private func deployClicked() {
        guard !isDeploying else { return }
        isDeploying = true
        deployButton.isEnabled = false
        deployButton.title = "Deploying..."
        resultLabel.isHidden = true
        openBrowserButton.isHidden = true
        resultURL = nil
        logTextView.string = ""
        let platform = platform
        let domain = domainCheck.state == .on ? domainField.stringValue : nil
        let service = service
        let folder = workspaceFolder
        Task {
            do {
                let result = try await service.deploy(platform: platform, workspaceFolder: folder, domain: domain) { [weak self] line in
                    Task { @MainActor in self?.appendLog(line) }
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isDeploying = false
                    self.deployButton.isEnabled = true
                    self.deployButton.title = "Start Deployment"
                    if result.success, let urlString = result.url, let url = URL(string: urlString) {
                        self.resultURL = url
                        self.resultLabel.stringValue = "Deployment Successful: \(urlString)"
                        self.resultLabel.isHidden = false
                        self.openBrowserButton.isHidden = false
                    } else {
                        self.appendLog(result.errorMessage ?? "Deployment failed.")
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isDeploying = false
                    self.deployButton.isEnabled = true
                    self.deployButton.title = "Start Deployment"
                    self.appendLog("DEPLOYMENT FAILED: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func openInBrowser() {
        guard let resultURL else { return }
        NSWorkspace.shared.open(resultURL)
    }

    func appendLog(_ line: String) {
        let text = logTextView.string
        logTextView.string = text.isEmpty ? line : text + "\n" + line
        logTextView.scrollToEndOfDocument(nil)
    }
}
