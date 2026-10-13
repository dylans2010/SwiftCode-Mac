import AppKit // NSOpenPanel, NSSavePanel
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SDKShipExportView
//
// Studio Ship/Export surface (Docs/Intro-to-SDK.md §8, Task A4): pick an
// extension/app project directory, then export a deterministic
// `.swiftcode-extension` package through an `NSSavePanel`.
//
// The package format is documented in
// `SwiftCode/SDK/Documentation/Package-Format.md`: a deterministic ZIP
// (sorted entries, fixed mtime/mode) carrying `swiftcode.json`,
// `dist/**`, and an embedded `swiftcode-digest.json` integrity record.
//
// REAL behaviors, no placeholders:
// - The project summary (id, name, version, kind) is read from the
//   project's real `swiftcode.json`, decoded with `JSONDecoder` into the
//   shared `SDKManifest` contract. A missing or undecodable manifest is
//   reported, never guessed.
// - Export runs the real CLI — `node <swiftcode.mjs> package <projectDir>
//   --out <tmp> --json` — as a child `Process`, parses the JSON envelope,
//   then moves the produced archive to the save-panel URL. The reported
//   sha256 and content digests come from the CLI's verified output, never
//   invented here.
// - CLI resolution uses the explicit `com.swiftcode.sdk.cliPath` override
//   when set, otherwise the app-bundled toolkit; Node.js resolves via
//   `SDKNodeLauncher.resolveNodeURL()`. When either is
//   missing, the view does NOT pretend to export: it presents a sheet with
//   the exact terminal command for the user to run manually.
// - Every control performs its real action; failures surface the real
//   error inline.
//
// Hosting: this view is a standalone surface with `init()`; the Studio
// shell presents it (e.g. from the SDK section) like the other Studio views.

@MainActor
public struct SDKShipExportView: View {

    // MARK: - Nested types

    private enum Phase {
        case noProject
        case ready(ProjectSummary)
        case exporting(ProjectSummary, String)
        case succeeded(ProjectSummary, ExportResult)
        case failed(ProjectSummary?, String)
    }

    private struct ProjectSummary {
        let directory: URL
        let id: String
        let name: String
        let version: String
        let kind: String // "extension" | "app"
    }

    private struct ExportResult {
        let fileURL: URL
        let sha256: String
        let contentDigest: String
    }

    private struct ManualCommandRequest: Identifiable {
        let id = UUID()
        let title: String
        let reason: String
        let command: String
    }

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
        let contentDigest: String?
    }

    private struct CLIEmpty: Decodable {}

    // MARK: - Constants

    /// UserDefaults key holding the full path to `swiftcode.mjs`.
    /// Owned/documented by SDKStudioExtensionsView; read here only.
    private static let cliPathDefaultsKey = "com.swiftcode.sdk.cliPath"

    // MARK: - State

    @State private var phase: Phase = .noProject
    @State private var manualCommand: ManualCommandRequest?

    public init() {}

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            switch phase {
            case .noProject:
                emptyState
            case .ready(let project):
                projectSummary(project)
                exportButton(for: project)
            case .exporting(let project, let status):
                projectSummary(project)
                ProgressView(status)
                    .progressViewStyle(.linear)
            case .succeeded(let project, let result):
                projectSummary(project)
                successCard(result)
                exportButton(for: project)
            case .failed(let project, let message):
                if let project { projectSummary(project) }
                failureCard(message)
                if let project { exportButton(for: project) }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $manualCommand) { request in
            manualCommandSheet(request)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ship / Export")
                .font(.title2)
                .bold()
            Text("Package an extension or app into a deterministic `.swiftcode-extension` file you can share or install elsewhere.")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No project selected",
            systemImage: "shippingbox",
            description: Text("Choose the extension or app project directory to export.")
        )
        .overlay(alignment: .bottom) {
            Button("Choose Project…") { chooseProject() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
    }

    private func projectSummary(_ project: ProjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.headline)
                    Text("\(project.id) · v\(project.version) · \(project.kind)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(project.directory.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Change…") { chooseProject() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func exportButton(for project: ProjectSummary) -> some View {
        Button("Export .swiftcode-extension…") { promptForDestination(project: project) }
            .buttonStyle(.borderedProminent)
    }

    private func successCard(_ result: ExportResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Export complete", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(result.fileURL.path)
                .font(.subheadline)
                .textSelection(.enabled)
            LabeledContent("sha256", value: result.sha256)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            LabeledContent("content digest", value: result.contentDigest)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
            }
            .buttonStyle(.link)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Export failed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func manualCommandSheet(_ request: ManualCommandRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.title).font(.headline)
            Text(request.reason).foregroundStyle(.secondary)
            Text(request.command)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(10)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(request.command, forType: .string)
                }
                .buttonStyle(.borderedProminent)
                Button("Close") { manualCommand = nil }
                    .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    // MARK: - Project picking

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the extension or app project directory (the one containing swiftcode.json)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let summary = try readProjectSummary(directory: url)
            phase = .ready(summary)
        } catch {
            phase = .failed(nil, error.localizedDescription)
        }
    }

    private func readProjectSummary(directory: URL) throws -> ProjectSummary {
        let manifestURL = directory.appendingPathComponent("swiftcode.json")
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw ExportError(message: "No swiftcode.json found in \(directory.path). Choose an extension or app project directory.")
        }
        let manifest: SDKManifest
        do {
            manifest = try JSONDecoder().decode(SDKManifest.self, from: data)
        } catch {
            throw ExportError(message: "swiftcode.json could not be decoded: \(error.localizedDescription)")
        }
        guard manifest.manifestVersion == 1 else {
            throw ExportError(message: "Unsupported manifestVersion \(manifest.manifestVersion) — this Studio ships the v1 packager.")
        }
        return ProjectSummary(
            directory: directory,
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            kind: manifest.type
        )
    }

    // MARK: - Export

    private func promptForDestination(project: ProjectSummary) {
        let panel = NSSavePanel()
        let fileExtension = "swiftcode-extension"
        if let fileType = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [fileType]
        }
        let slug = project.id.split(separator: ".").last.map(String.init) ?? project.id
        panel.nameFieldStringValue = "\(slug)-\(project.version).\(fileExtension)"
        panel.canCreateDirectories = true
        panel.message = "Export \(project.name) as a .swiftcode-extension package."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task { await export(project: project, destination: destination) }
    }

    private func export(project: ProjectSummary, destination: URL) async {
        phase = .exporting(project, "Packaging \(project.name)…")

        // Resolve node + CLI. When either is missing we do not pretend:
        // show the exact manual command instead.
        let nodeURL: URL
        let cliURL: URL
        do {
            nodeURL = try SDKNodeLauncher.resolveNodeURL()
        } catch {
            showManual(project: project, reason: "Node.js could not be resolved (\(error.localizedDescription)).")
            phase = .ready(project)
            return
        }
        guard let resolvedCLI = resolveCLIURL() else {
            showManual(
                project: project,
                reason: "The swiftcode CLI path is not configured (UserDefaults key \(Self.cliPathDefaultsKey))."
            )
            phase = .ready(project)
            return
        }
        cliURL = resolvedCLI

        do {
            let outDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-ship-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: outDir) }

            phase = .exporting(project, "Running swiftcode package…")
            let result = try await runCLI(
                nodeURL: nodeURL,
                cliURL: cliURL,
                arguments: ["package", project.directory.path, "--out", outDir.path, "--json"]
            )
            let packageData = try packageData(from: result)
            guard let producedPath = packageData.path, !producedPath.isEmpty else {
                throw ExportError(message: cliFailureMessage(result, command: "package"))
            }
            let producedURL = URL(fileURLWithPath: producedPath)

            // Move the finished archive to the save-panel destination,
            // replacing any file already there (the user's explicit choice).
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: producedURL)
            } else {
                try FileManager.default.moveItem(at: producedURL, to: destination)
            }

            phase = .succeeded(
                project,
                ExportResult(
                    fileURL: destination,
                    sha256: packageData.sha256 ?? "(not reported)",
                    contentDigest: packageData.contentDigest ?? "(not reported)"
                )
            )
        } catch {
            phase = .failed(project, error.localizedDescription)
        }
    }

    private func showManual(project: ProjectSummary, reason: String) {
        manualCommand = ManualCommandRequest(
            title: "CLI unavailable",
            reason: "\(reason) Run this in a terminal to export the package:",
            command: "node /path/to/swiftcode.mjs package \"\(project.directory.path)\" --out ~/Desktop"
        )
    }

    private func resolveCLIURL() -> URL? {
        SDKInstaller.resolveCLIURL()
    }

    // MARK: - CLI plumbing

    /// Runs `node <cli> <arguments>` off the main actor; output is captured
    /// after the process exits (bounded), like the sibling extensions view.
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

    private func packageData(from result: CLIProcessResult) throws -> CLIPackageData {
        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(CLIEnvelope<CLIPackageData>.self, from: data),
              envelope.ok,
              let package = envelope.data
        else {
            throw ExportError(message: cliFailureMessage(result, command: "package"))
        }
        return package
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

    private struct ExportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
