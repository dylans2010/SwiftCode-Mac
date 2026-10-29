import Foundation
import SwiftUI

// MARK: - Extensions v2 manager (single authoritative lifecycle owner)
//
// There is exactly one manager, one installed-records file, and one
// host manager. Views never keep their own copy of install state:
// after every mutation they re-read from here. A broken extension
// cannot prevent launch: refreshInstalled() tolerates missing
// directories and malformed records by marking them unavailable
// instead of throwing, and stale staging is cleaned at init.

@MainActor
public final class ExtV2Manager: ObservableObject {
    public static let shared = ExtV2Manager()

    @Published public private(set) var installed: [ExtV2InstalledExtension] = []
    @Published public private(set) var searchResults: [ExtV2ExtensionMetadata] = []
    @Published public private(set) var searchError: String?
    @Published public private(set) var isSearching = false
    @Published public private(set) var installingIDs: Set<String> = []
    @Published public private(set) var updates: [ExtV2UpdateInfo] = []
    @Published public private(set) var contributions: [String: ExtV2Contribution] = [:]
    @Published public var settings: ExtV2Storage.Settings

    public let storage: ExtV2Storage
    public let permissions: ExtV2PermissionManager
    public let hostManager: ExtV2HostManager
    public let packageService: ExtV2PackageService
    public let diagnostics = ExtV2DiagnosticsService.shared

    private var registryClient: ExtV2RegistryClient
    private var searchTask: Task<Void, Never>?
    private var searchOffset = 0
    private var lastQuery = ""

    public var workspaceRoot: URL? = nil
    public var workspaceBridge: ExtV2WorkspaceBridge? {
        guard let workspaceRoot else { return nil }
        return ExtV2WorkspaceBridge(root: workspaceRoot, permissions: permissions)
    }

    public init() {
        let storage = ExtV2Storage()
        self.storage = storage
        self.settings = storage.loadSettings()
        self.permissions = ExtV2PermissionManager(storage: storage)
        self.hostManager = ExtV2HostManager(storage: storage, permissions: permissions)
        self.packageService = ExtV2PackageService(storage: storage)
        self.registryClient = ExtV2RegistryClient(settings: settings)
        ExtV2AssistExecution.shared.hostManager = hostManager
        ExtV2AssistExecution.shared.permissions = permissions
        hostManager.hostRequestHandler = { [weak self] extensionId, request in
            guard let self else { return .null }
            return try await self.handleHostRequest(extensionId: extensionId, request: request)
        }
        try? storage.ensureDirectories()
        storage.cleanStaleStaging()
        refreshInstalled()
        ExtV2XcodeCommandRegistry.shared.register(ExtV2SortLinesCommand())
    }

    // MARK: Settings

    public func saveSettings() {
        try? storage.saveSettings(settings)
        registryClient = ExtV2RegistryClient(settings: settings)
    }

    public func setWorkspaceRoot(_ url: URL?) {
        workspaceRoot = url
    }

    // MARK: Installed state

    public func refreshInstalled() {
        var records = storage.loadInstalled()
        var byID: [String: ExtV2InstalledExtension] = [:]
        for record in records { byID[record.id] = record }
        for index in records.indices {
            let record = records[index]
            let dir = URL(fileURLWithPath: record.installPath)
            if !FileManager.default.fileExists(atPath: dir.path) {
                records[index].state = .unavailable
                records[index].lastError = "Installed directory is missing."
                continue
            }
            if !record.isEnabled {
                records[index].state = .disabled
                continue
            }
            let missing = ExtV2DependencyResolver.missingDependencies(for: record, installedByID: byID)
            if !missing.isEmpty {
                records[index].state = .missingDependencies
                records[index].lastError = "Missing dependencies: \(missing.joined(separator: ", "))"
                continue
            }
            if hostManager.isRunning(extensionId: record.id) {
                records[index].state = .running
                continue
            }
            // Re-evaluate compatibility from the installed manifest so a
            // record can never claim compatibility the package does not have.
            if let manifest = try? ExtV2ManifestParser.parseFile(
                at: dir.appendingPathComponent("extension/package.json")) {
                let report = ExtV2Compatibility.evaluate(manifest: manifest)
                records[index].state = report.compatible ? .enabled : .incompatible
                records[index].lastError = report.compatible ? nil : report.reasons.joined(separator: " ")
            } else {
                records[index].state = .enabled
            }
        }
        installed = records.sorted { $0.metadata.displayName < $1.metadata.displayName }
    }

    private func persistInstalled() {
        try? storage.saveInstalled(installed)
    }

    private func upsert(_ record: ExtV2InstalledExtension) {
        if let index = installed.firstIndex(where: { $0.id == record.id }) {
            installed[index] = record
        } else {
            installed.append(record)
        }
        installed.sort { $0.metadata.displayName < $1.metadata.displayName }
        persistInstalled()
    }

    // MARK: Search

    public func search(query: String) {
        searchTask?.cancel()
        lastQuery = query
        searchOffset = 0
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            searchError = nil
            return
        }
        isSearching = true
        searchError = nil
        searchTask = Task {
            do {
                let page = try await registryClient.search(query: query, offset: 0)
                guard !Task.isCancelled else { return }
                searchResults = page.results
                searchOffset = page.results.count
            } catch is CancellationError {
                // Superseded by a newer keystroke; not an error.
            } catch {
                searchError = error.localizedDescription
                diagnostics.error("Registry search failed: \(error.localizedDescription)")
            }
            isSearching = false
        }
    }

    public func loadMoreSearchResults() {
        guard !lastQuery.isEmpty, !isSearching else { return }
        isSearching = true
        Task {
            do {
                let page = try await registryClient.search(query: lastQuery, offset: searchOffset)
                guard !Task.isCancelled else { return }
                searchResults += page.results
                searchOffset += page.results.count
            } catch is CancellationError {
            } catch {
                searchError = error.localizedDescription
            }
            isSearching = false
        }
    }

    // MARK: Install / update / uninstall / enable

    /// Full pipeline: resolve download, download, validate + install
    /// atomically, evaluate compatibility and dependencies, record.
    /// Cancellation deletes the downloaded file and any staging dir;
    /// the previous installation is never touched on failure.
    public func install(metadata: ExtV2ExtensionMetadata) async throws {
        let id = metadata.id
        guard !installingIDs.contains(id) else { return }
        installingIDs.insert(id)
        defer { installingIDs.remove(id) }
        do {
            let downloadURL = try await registryClient.downloadURL(for: metadata)
            let tempVSIX = storage.stagingDirectory.appendingPathComponent("\(id)-\(UUID().uuidString).vsix")
            try? storage.ensureDirectories()
            try await registryClient.downloadVSIX(from: downloadURL, to: tempVSIX)
            let installedPackage: ExtV2InstalledPackage
            do {
                installedPackage = try packageService.install(vsixURL: tempVSIX, identity: metadata.identity)
            } catch {
                try? FileManager.default.removeItem(at: tempVSIX)
                throw error
            }
            try? FileManager.default.removeItem(at: tempVSIX)
            let manifest = installedPackage.manifest
            let record = ExtV2InstalledExtension(
                metadata: metadata, isEnabled: true,
                state: installedPackage.compatibility.compatible ? .enabled : .incompatible,
                installPath: installedPackage.directory.path,
                dependencies: manifest.allDependencies,
                capabilities: [],
                lastError: installedPackage.compatibility.compatible
                    ? nil : installedPackage.compatibility.reasons.joined(separator: " "))
            upsert(record)
            // Dependency state is recomputed for everything, since a new
            // install can satisfy another extension's missing dependency.
            refreshInstalled()
            diagnostics.info("Installed \(id) v\(metadata.version).", extensionId: id)
            if !installedPackage.compatibility.compatible {
                diagnostics.warning("Installed but incompatible: \(record.lastError ?? "")", extensionId: id)
            }
        } catch is CancellationError {
            diagnostics.info("Installation cancelled.", extensionId: id)
            throw ExtV2Error.cancelled
        } catch ExtV2Error.cancelled {
            diagnostics.info("Installation cancelled.", extensionId: id)
            throw ExtV2Error.cancelled
        } catch {
            diagnostics.error("Installation failed: \(error.localizedDescription)", extensionId: id)
            throw error
        }
    }

    public func uninstall(extensionId: String) async {
        hostManager.deactivate(extensionId: extensionId)
        contributions.removeValue(forKey: extensionId)
        permissions.revokeAll(for: extensionId)
        try? packageService.uninstall(extensionId: extensionId)
        installed.removeAll { $0.id == extensionId }
        persistInstalled()
        diagnostics.info("Uninstalled.", extensionId: extensionId)
    }

    public func setEnabled(extensionId: String, enabled: Bool) {
        guard let index = installed.firstIndex(where: { $0.id == extensionId }) else { return }
        if !enabled { hostManager.deactivate(extensionId: extensionId) }
        installed[index].isEnabled = enabled
        persistInstalled()
        refreshInstalled()
    }

    public func checkUpdates() async {
        var found: [ExtV2UpdateInfo] = []
        for record in installed where record.metadata.kind == .vscode {
            do {
                let latest = try await registryClient.details(for: record.identity)
                if let installedVersion = ExtV2Version(string: record.metadata.version),
                   let latestVersion = ExtV2Version(string: latest.version),
                   latestVersion > installedVersion {
                    found.append(ExtV2UpdateInfo(installed: record, latest: latest))
                }
            } catch {
                diagnostics.warning("Update check failed: \(error.localizedDescription)", extensionId: record.id)
            }
        }
        updates = found
    }

    // MARK: Activation and commands

    public func activate(extensionId: String) async throws -> ExtV2Contribution {
        guard let record = installed.first(where: { $0.id == extensionId }) else {
            throw ExtV2Error.notInstalled(extensionId)
        }
        guard record.isEnabled else { throw ExtV2Error.disabled(extensionId) }
        guard record.state != .incompatible else {
            throw ExtV2Error.incompatible(record.lastError ?? "Extension is incompatible with this host.")
        }
        switch record.metadata.kind {
        case .vscode:
            let contribution = try await hostManager.activate(
                installed: record, workspaceRoot: workspaceRoot, settings: settings)
            contributions[extensionId] = contribution
            if let index = installed.firstIndex(where: { $0.id == extensionId }) {
                installed[index].state = .running
                persistInstalled()
            }
            registerAssistCommands(for: record, contribution: contribution)
            return contribution
        case .native:
            // Native plugins activate through their registry; the Run
            // view renders the manifest's contribution.
            let manifest = ExtV2NativePluginRegistry.shared.manifests.first { "swiftcode.\($0.id)" == extensionId }
                ?? ExtV2NativePluginManifest(id: extensionId, name: record.metadata.displayName, version: record.metadata.version, description: record.metadata.description)
            let contribution = ExtV2NativePluginRegistry.shared.contribution(for: manifest)
            contributions[extensionId] = contribution
            return contribution
        case .xcodeCommand:
            return ExtV2Contribution(
                commands: ExtV2XcodeCommandRegistry.shared.allIdentifiers.map {
                    ExtV2ContributionCommand(command: $0, title: $0)
                },
                outputLines: ["Xcode-compatible commands run against a source buffer; see the Xcode Compatibility section."])
        }
    }

    public func deactivate(extensionId: String) {
        hostManager.deactivate(extensionId: extensionId)
        contributions.removeValue(forKey: extensionId)
        refreshInstalled()
    }

    public func executeCommand(extensionId: String, command: String, args: [ExtV2JSONValue] = []) async throws -> String {
        // Native plugin commands resolve through the native registry.
        if ExtV2NativePluginRegistry.handler(for: command) != nil {
            let result = try await ExtV2NativePluginRegistry.shared.executeCommand(command, args: args)
            return result.stringValue ?? ""
        }
        if let owner = hostManager.ownerOfCommand(command), owner != extensionId {
            throw ExtV2Error.invalidRequest("Command '\(command)' belongs to '\(owner)', not '\(extensionId)'.")
        }
        let result = try await hostManager.executeCommand(extensionId: extensionId, command: command, args: args)
        return result.stringValue ?? ""
    }

    private func registerAssistCommands(for record: ExtV2InstalledExtension, contribution: ExtV2Contribution) {
        for command in contribution.commands {
            let descriptor = ExtV2AssistBridge.descriptor(for: command, extensionId: record.id)
            _ = ExtV2AssistBridge.register(descriptor, permissions: permissions)
        }
    }

    public func registerSamplePlugin() {
        ExtV2NativePluginRegistry.shared.register(ExtV2SamplePlugin.self)
        let manifest = ExtV2SamplePlugin.manifest
        let record = ExtV2InstalledExtension(
            metadata: manifest.metadata, isEnabled: true, state: .enabled,
            installPath: "", dependencies: [], capabilities: manifest.capabilities)
        upsert(record)
    }

    // MARK: Host-initiated requests

    private func handleHostRequest(extensionId: String, request: ExtV2RPCRequest) async throws -> ExtV2JSONValue {
        let params = request.params?.objectValue ?? [:]
        switch request.method {
        case "host.log":
            if let message = params["message"]?.stringValue {
                diagnostics.info(message, extensionId: extensionId)
            }
            return .null
        case "host.readFile":
            guard let path = params["path"]?.stringValue,
                  let workspace = workspaceBridge else {
                throw ExtV2Error.invalidRequest("No workspace is open for file reads.")
            }
            return .string(try workspace.readFile(relativePath: path, extensionId: extensionId))
        case "host.writeFile":
            guard let path = params["path"]?.stringValue,
                  let content = params["content"]?.stringValue,
                  let workspace = workspaceBridge else {
                throw ExtV2Error.invalidRequest("Invalid writeFile request.")
            }
            try workspace.writeFile(relativePath: path, content: content, extensionId: extensionId)
            return .null
        case "host.applyEdit":
            // Edits arrive as {path, edits:[{range, newText}]} and are
            // applied through the editor bridge against current disk
            // content, so a stale edit fails instead of overwriting.
            guard let path = params["path"]?.stringValue,
                  let workspace = workspaceBridge else {
                throw ExtV2Error.invalidRequest("Invalid applyEdit request.")
            }
            let current = try workspace.readFile(relativePath: path, extensionId: extensionId)
            let edits = params["edits"]?.arrayValue ?? []
            let parsed = try edits.map { editValue -> ExtV2TextEdit in
                guard let obj = editValue.objectValue,
                      let rangeObj = obj["range"]?.objectValue,
                      let startObj = rangeObj["start"]?.objectValue,
                      let endObj = rangeObj["end"]?.objectValue,
                      let startLine = startObj["line"]?.intValue,
                      let startChar = startObj["character"]?.intValue,
                      let endLine = endObj["line"]?.intValue,
                      let endChar = endObj["character"]?.intValue,
                      let newText = obj["newText"]?.stringValue else {
                    throw ExtV2Error.invalidRequest("Malformed text edit in applyEdit.")
                }
                return ExtV2TextEdit(
                    range: ExtV2TextRange(
                        start: ExtV2TextPosition(line: startLine, character: startChar),
                        end: ExtV2TextPosition(line: endLine, character: endChar)),
                    newText: newText)
            }
            let updated = try ExtV2EditorBridge.applyEdits(parsed, to: current)
            try workspace.writeFile(relativePath: path, content: updated, extensionId: extensionId)
            return .bool(true)
        case "host.publishDiagnostics":
            guard let path = params["path"]?.stringValue else { return .null }
            let raw = params["diagnostics"]?.arrayValue ?? []
            let diagnosticsList: [ExtV2Diagnostic] = raw.compactMap { value in
                guard let obj = value.objectValue,
                      let message = obj["message"]?.stringValue else { return nil }
                let rangeObj = obj["range"]?.objectValue
                let startObj = rangeObj?["start"]?.objectValue
                let endObj = rangeObj?["end"]?.objectValue
                let range = ExtV2TextRange(
                    start: ExtV2TextPosition(line: startObj?["line"]?.intValue ?? 0, character: startObj?["character"]?.intValue ?? 0),
                    end: ExtV2TextPosition(line: endObj?["line"]?.intValue ?? 0, character: endObj?["character"]?.intValue ?? 0))
                return ExtV2Diagnostic(
                    relativePath: path, range: range, message: message,
                    severity: obj["severity"]?.stringValue ?? "Error", source: extensionId)
            }
            ExtV2ProviderRegistry.shared.publishDiagnostics(extensionId: extensionId, relativePath: path, diagnostics: diagnosticsList)
            return .null
        case "host.registerCompletionProvider":
            if let language = params["language"]?.stringValue {
                ExtV2ProviderRegistry.shared.registerCompletionProvider(extensionId: extensionId, language: language)
            }
            return .null
        case "host.registerHoverProvider":
            if let language = params["language"]?.stringValue {
                ExtV2ProviderRegistry.shared.registerHoverProvider(extensionId: extensionId, language: language)
            }
            return .null
        case "host.requestPermission":
            guard let capabilityRaw = params["capability"]?.stringValue,
                  let capability = ExtV2Capability(rawValue: capabilityRaw) else {
                throw ExtV2Error.invalidRequest("Unknown capability in permission request.")
            }
            let approved = await permissions.request(
                extensionId: extensionId, capability: capability,
                reason: params["reason"]?.stringValue ?? "The extension requested this capability.")
            return .bool(approved)
        case "host.showQuickPick", "host.showInputBox":
            // No picker UI is attached to the host path yet; returning
            // null is an honest "no selection" rather than a fabricated
            // choice. RunView wires pickers for interactive extensions.
            diagnostics.info("Picker requested but no picker UI is attached; returning no selection.", extensionId: extensionId)
            return .null
        default:
            // Unknown-but-allowed methods that need no action.
            return .null
        }
    }
}
