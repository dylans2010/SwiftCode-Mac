import AppKit
import Foundation
import SwiftUI

// MARK: - SDKStudioExtensionsView
//
// Extension lifecycle console (spec Docs/Intro-to-SDK.md §13.3): the Studio
// surface for testing, enabling, disabling, updating, packaging, and
// uninstalling locally installed extensions.
//
// Sibling-view contract (owned by parallel work — referenced here by their
// exact names and inits, never redefined):
//   - SDKManifestInspectorView(extensionID: String)
//   - SDKGrantManagerView(extensionID: String)
//
// This view is hosted inside the Studio shell's NavigationStack; it does
// not create its own navigation container.
//
// Real work only: every control calls a real API. Scan/enable/uninstall go
// through SDKExtensionRegistry; uninstall additionally revokes every
// capability grant via SDKGrantStore so no grant survives its extension
// (spec §8.7). Package/install/update/validate shell out to the real
// SwiftCode CLI through a child node process. Errors are shown inline and
// are never swallowed.
//
// CLI resolution uses the explicit com.swiftcode.sdk.cliPath developer
// override when set; otherwise it uses the app-bundled toolkit. Missing
// Node or CLI is reported with manual commands, never fake success.

@MainActor
public struct SDKStudioExtensionsView: View {

    // MARK: - Nested types

    /// Which directory-picking flow is waiting on the NSOpenPanel result.
    private enum DirectoryAction {
        case packageInstall
        case update(ext: SDKInstalledExtension)
    }

    /// What the user asked to do when the CLI turned out to be unreachable,
    /// so the manual-command sheet can render the exact commands.
    private enum ManualOp {
        case packageInstall(sourceDir: URL)
        case update(ext: SDKInstalledExtension, sourceDir: URL)
        case validate(ext: SDKInstalledExtension)
    }

    /// The completed result of one CLI child-process invocation.
    private struct CLIProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private struct CLIErrorBody: Decodable {
        let code: String?
        let message: String?
    }

    private struct CLIEnvelope<Payload: Decodable>: Decodable {
        let ok: Bool
        let data: Payload?
        let error: CLIErrorBody?
    }

    private struct CLIPackageData: Decodable {
        let path: String?
        let sha256: String?
    }

    private struct CLIEmpty: Decodable {}

    private struct CLIFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct ManualCommandRequest: Identifiable {
        let id = UUID()
        let title: String
        let reason: String
        let command: String
    }

    // MARK: - Constants

    /// UserDefaults key holding the full path to `swiftcode.mjs`. See the
    /// CLI REACHABILITY DECISION note at the top of this file.
    private static let cliPathDefaultsKey = "com.swiftcode.sdk.cliPath"

    // MARK: - State

    @State private var extensions: [SDKInstalledExtension] = []
    @State private var selection: String?
    // Starts true so the first paint doesn't flash the "no extensions"
    // empty state before the initial scan completes.
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var confirmingUninstall = false
    @State private var validatingExtensionID: String?
    @State private var pendingDirectoryAction: DirectoryAction?
    @State private var manualCommand: ManualCommandRequest?

    public init() {}

    // MARK: - Derived

    private var selectedExtension: SDKInstalledExtension? {
        guard let selection else { return nil }
        return extensions.first { $0.id == selection }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                errorBanner(message: errorMessage)
            }
            if let statusMessage {
                statusBanner(message: statusMessage)
            }
            if extensions.isEmpty && !isLoading {
                emptyState
            } else {
                extensionList
            }
        }
        .navigationTitle("Extensions")
        .toolbar { toolbarContent }
        .task { await refresh() }
        .alert(
            "Uninstall Extension?",
            isPresented: $confirmingUninstall,
            presenting: selectedExtension
        ) { ext in
            Button("Uninstall", role: .destructive) { uninstall(ext) }
            Button("Cancel", role: .cancel) {}
        } message: { ext in
            Text("Remove “\(ext.name)” version \(ext.version) and revoke all of its capability grants? This cannot be undone.")
        }
        .sheet(item: $manualCommand) { request in
            manualCommandSheet(request)
        }
    }

    // MARK: - List

    private var extensionList: some View {
        List(extensions, id: \.id, selection: $selection) { ext in
            extensionRow(ext)
                .tag(ext.id)
        }
    }

    private func extensionRow(_ ext: SDKInstalledExtension) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ext.name).font(.headline)
                    Text(ext.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { ext.enabled },
                    set: { setEnabled(ext, to: $0) }
                ))
            }
            HStack(spacing: 12) {
                Text("Version \(ext.version)").font(.subheadline)
                HStack(spacing: 4) {
                    Text("Digest:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(truncatedDigest(ext.packageDigest))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                        .help("Full SHA-256 package digest:\n\(ext.packageDigest)")
                }
            }
            HStack(spacing: 16) {
                NavigationLink("Manifest") {
                    SDKManifestInspectorView(installedExtension: ext)
                }
                NavigationLink("Grants") {
                    SDKGrantManagerView(extensionID: ext.id)
                }
                Spacer()
                if validatingExtensionID == ext.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Validate") { validate(ext) }
                        .disabled(isBusy)
                        .help("Test: run the CLI validator against the installed extension.")
                }
                Button("Update…") { beginUpdate(ext) }
                    .disabled(isBusy)
            }
            .buttonStyle(.link)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Extensions Installed", systemImage: "puzzlepiece.extension")
        } description: {
            Text("No extensions installed — create one in Projects or install a .swiftcode-extension package.")
        } actions: {
            Button("Package & Install…") { beginPackageInstall() }
                .disabled(isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await refresh() }
            }
            .disabled(isLoading || isBusy)
            .help("Re-scan the installed extensions directory.")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Uninstall", systemImage: "trash") {
                confirmingUninstall = true
            }
            .disabled(selection == nil || isBusy)
            .help("Uninstall the selected extension and revoke its capability grants.")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Package & Install…", systemImage: "archivebox") {
                beginPackageInstall()
            }
            .disabled(isBusy)
            .help("Package an extension project directory and install it.")
        }
    }

    // MARK: - Banners and sheets

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .textSelection(.enabled)
            Spacer()
            Button("Dismiss") { errorMessage = nil }
                .buttonStyle(.link)
        }
        .padding(8)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding([.horizontal, .top], 8)
    }

    private func statusBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.blue)
            Text(message)
                .textSelection(.enabled)
            Spacer()
            Button("Dismiss") { statusMessage = nil }
                .buttonStyle(.link)
        }
        .padding(8)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding([.horizontal, .top], 8)
    }

    private func manualCommandSheet(_ request: ManualCommandRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.title).font(.headline)
            Text(request.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Set the UserDefaults key “com.swiftcode.sdk.cliPath” to the full path of swiftcode.mjs in your SwiftCode-Mac checkout (…/SwiftCode/SDK/TypeScript/cli/swiftcode.mjs). Until then, run these commands in Terminal — they perform the same steps:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(request.command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button("Copy Command") { copyToPasteboard(request.command) }
                Spacer()
                Button("Close") { manualCommand = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 320)
        .liquidGlass(style: .sheet, cornerRadius: 12)
    }

    // MARK: - Scan / enable / uninstall (registry + grant store)

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await SDKExtensionRegistry.shared.scan()
            extensions = found
            if let selection, !found.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
        } catch {
            showError(error)
        }
    }

    private func setEnabled(_ ext: SDKInstalledExtension, to enabled: Bool) {
        Task {
            clearMessages()
            do {
                try await SDKExtensionRegistry.shared.setEnabled(enabled, extensionID: ext.id)
                await refresh()
            } catch {
                showError(error)
                // Restore the toggle to the stored value on failure.
                await refresh()
            }
        }
    }

    private func uninstall(_ ext: SDKInstalledExtension) {
        Task {
            clearMessages()
            do {
                // The runtime coordinator deactivates the extension
                // separately; the registry owns only the install record.
                try await SDKExtensionRegistry.shared.removeInstallRecord(
                    extensionID: ext.id,
                    version: ext.version
                )
                // Grants must die with the extension (spec §8.7).
                try await SDKGrantStore.shared.revokeAll(for: ext.id)
                selection = nil
                statusMessage = "Uninstalled “\(ext.name)” and revoked its capability grants."
                await refresh()
            } catch {
                showError(error)
            }
        }
    }

    // MARK: - Directory picking (NSOpenPanel)

    private func beginPackageInstall() {
        pendingDirectoryAction = .packageInstall
        presentDirectoryPicker(title: "Choose Extension Project", prompt: "Package & Install")
    }

    private func beginUpdate(_ ext: SDKInstalledExtension) {
        pendingDirectoryAction = .update(ext: ext)
        presentDirectoryPicker(title: "Choose Updated Extension Source", prompt: "Update")
    }

    private func presentDirectoryPicker(title: String, prompt: String) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.begin { [weak panel] response in
            // AppKit invokes the begin(completionHandler:) handler on the main thread.
            let url = response == .OK ? panel?.url : nil
            MainActor.assumeIsolated { self.directoryPicked(url) }
        }
    }

    private func directoryPicked(_ url: URL?) {
        let action = pendingDirectoryAction
        pendingDirectoryAction = nil
        guard let url, let action else { return }
        switch action {
        case .packageInstall:
            runPackageInstall(sourceDir: url)
        case .update(let ext):
            runUpdate(ext, sourceDir: url)
        }
    }

    // MARK: - CLI-backed flows (package / install / update / validate)

    private func runPackageInstall(sourceDir: URL) {
        Task {
            clearMessages()
            statusMessage = "Packaging extension…"
            guard let (nodeURL, cliURL) = cliPrerequisites(for: .packageInstall(sourceDir: sourceDir)) else { return }
            isBusy = true
            defer { isBusy = false }
            do {
                let outDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("swiftcode-sdk-package-\(UUID().uuidString)", isDirectory: true)
                let packageResult = try await runCLI(
                    nodeURL: nodeURL,
                    cliURL: cliURL,
                    arguments: ["package", sourceDir.path, "--out", outDir.path, "--json"]
                )
                let packagePath = try packagedPath(from: packageResult)
                statusMessage = "Installing package…"
                let installResult = try await runCLI(
                    nodeURL: nodeURL,
                    cliURL: cliURL,
                    arguments: ["install", packagePath, "--json"]
                )
                try checkCLIResult(installResult, command: "install")
                try? FileManager.default.removeItem(at: outDir)
                statusMessage = "Extension packaged and installed."
                await refresh()
            } catch {
                showError(error)
            }
        }
    }

    private func runUpdate(_ ext: SDKInstalledExtension, sourceDir: URL) {
        Task {
            clearMessages()
            statusMessage = "Packaging updated extension…"
            guard let (nodeURL, cliURL) = cliPrerequisites(for: .update(ext: ext, sourceDir: sourceDir)) else { return }
            isBusy = true
            defer { isBusy = false }
            do {
                let outDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("swiftcode-sdk-package-\(UUID().uuidString)", isDirectory: true)
                let packageResult = try await runCLI(
                    nodeURL: nodeURL,
                    cliURL: cliURL,
                    arguments: ["package", sourceDir.path, "--out", outDir.path, "--json"]
                )
                let packagePath = try packagedPath(from: packageResult)
                statusMessage = "Installing update…"
                let installResult = try await runCLI(
                    nodeURL: nodeURL,
                    cliURL: cliURL,
                    arguments: ["install", packagePath, "--update", "--json"]
                )
                try checkCLIResult(installResult, command: "install")
                try? FileManager.default.removeItem(at: outDir)
                statusMessage = "“\(ext.name)” updated."
                await refresh()
            } catch {
                showError(error)
            }
        }
    }

    private func validate(_ ext: SDKInstalledExtension) {
        Task {
            clearMessages()
            guard let (nodeURL, cliURL) = cliPrerequisites(for: .validate(ext: ext)) else { return }
            validatingExtensionID = ext.id
            isBusy = true
            defer {
                isBusy = false
                validatingExtensionID = nil
            }
            do {
                let result = try await runCLI(
                    nodeURL: nodeURL,
                    cliURL: cliURL,
                    arguments: ["validate", ext.installPath, "--json"]
                )
                try checkCLIResult(result, command: "validate")
                statusMessage = "“\(ext.name)” passed validation."
            } catch {
                showError(error)
            }
        }
    }

    // MARK: - CLI plumbing

    /// Resolves node + CLI, or presents the honest manual-command sheet and
    /// returns nil. Never throws: every failure is surfaced in the UI.
    private func cliPrerequisites(for op: ManualOp) -> (nodeURL: URL, cliURL: URL)? {
        let nodeURL: URL
        do {
            nodeURL = try SDKNodeLauncher.resolveNodeURL()
        } catch {
            showManualCommand(for: op, reason: userMessage(of: error))
            return nil
        }
        guard let cliURL = resolveCLIURL() else {
            let detail: String
            if let configured = configuredCLIPath(), !configured.isEmpty {
                detail = "The configured CLI path “\(configured)” does not name an existing file."
            } else {
                detail = "No CLI path is configured."
            }
            showManualCommand(for: op, reason: detail)
            return nil
        }
        return (nodeURL, cliURL)
    }

    private func configuredCLIPath() -> String? {
        UserDefaults.standard.string(forKey: Self.cliPathDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveCLIURL() -> URL? {
        SDKInstaller.resolveCLIURL()
    }

    /// Runs `node <cli> <arguments>` as a child process off the main actor
    /// and returns its exit code plus captured output. CLI stdout/stderr
    /// here are bounded summaries (never streaming logs), so they are read
    /// after the process exits.
    private func runCLI(nodeURL: URL, cliURL: URL, arguments: [String]) async throws -> CLIProcessResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = nodeURL
            process.arguments = [cliURL.path] + arguments
            process.environment = ProcessInfo.processInfo.environment
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()
            let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
            let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            return CLIProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }.value
    }

    private func packagedPath(from result: CLIProcessResult) throws -> String {
        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(CLIEnvelope<CLIPackageData>.self, from: data),
              envelope.ok,
              let path = envelope.data?.path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            throw CLIFailure(message: cliFailureMessage(result, command: "package"))
        }
        return path
    }

    private func checkCLIResult(_ result: CLIProcessResult, command: String) throws {
        guard result.exitCode == 0 else {
            throw CLIFailure(message: cliFailureMessage(result, command: command))
        }
        // Even at exit 0, honor an explicit ok:false envelope.
        if let data = result.stdout.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(CLIEnvelope<CLIEmpty>.self, from: data),
           !envelope.ok {
            throw CLIFailure(message: envelope.error?.message ?? "The CLI reported failure.")
        }
    }

    private func cliFailureMessage(_ result: CLIProcessResult, command: String) -> String {
        if let data = result.stdout.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(CLIEnvelope<CLIEmpty>.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return message
        }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        return "swiftcode \(command) exited with code \(result.exitCode) and produced no output."
    }

    // MARK: - Manual-command fallback

    private func showManualCommand(for op: ManualOp, reason: String) {
        statusMessage = nil
        manualCommand = ManualCommandRequest(
            title: manualTitle(for: op),
            reason: reason,
            command: manualCommandText(for: op)
        )
    }

    private func manualTitle(for op: ManualOp) -> String {
        switch op {
        case .packageInstall: return "Package & Install via Terminal"
        case .update: return "Update via Terminal"
        case .validate: return "Validate via Terminal"
        }
    }

    private func manualCommandText(for op: ManualOp) -> String {
        let cli = configuredCLIPath().flatMap { $0.isEmpty ? nil : $0 }
            ?? "<path-to-SwiftCode-Mac>/SwiftCode/SDK/TypeScript/cli/swiftcode.mjs"
        let quotedCLI = "\"\(cli)\""
        switch op {
        case .packageInstall(let sourceDir):
            return """
                node \(quotedCLI) package "\(sourceDir.path)" --json
                node \(quotedCLI) install "<package-file-from-step-1>" --json
                """
        case .update(_, let sourceDir):
            return """
                node \(quotedCLI) package "\(sourceDir.path)" --json
                node \(quotedCLI) install "<package-file-from-step-1>" --update --json
                """
        case .validate(let ext):
            return "node \(quotedCLI) validate \"\(ext.installPath)\" --json"
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: - Messaging helpers

    private func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    private func showError(_ error: Error) {
        statusMessage = nil
        if let sdkError = error as? SDKError {
            errorMessage = sdkError.userFacingDescription
        } else {
            errorMessage = error.localizedDescription
        }
    }

    private func userMessage(of error: Error) -> String {
        if let sdkError = error as? SDKError {
            if let suggestion = sdkError.suggestion, !suggestion.isEmpty {
                return "\(sdkError.message) \(suggestion)"
            }
            return sdkError.message
        }
        return error.localizedDescription
    }

    private nonisolated func truncatedDigest(_ digest: String) -> String {
        digest.count > 16 ? String(digest.prefix(16)) + "…" : digest
    }
}
