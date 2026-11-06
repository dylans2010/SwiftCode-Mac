import Foundation

/// The single lifecycle owner (spec §3.3). `@MainActor`, a singleton.
/// Views never keep their own copy of install state; after every
/// mutation they re-read from the manager.
///
/// Deviation from §10.6 (recorded): `init(storage:)` is added
/// alongside the spec's `init()` so tests can point the manager at a
/// temp directory. `init()` uses the default storage.
///
/// The MCP `use_extension` handler (in `SwiftCodeMCP`, not this target)
/// calls exactly these entry points plus
/// `permissions.grantedCapabilities(for:)`,
/// `diagnostics.entries(for:)`, the Xcode registry, and the native
/// registry.
@MainActor
public final class ExtensionManager {
    public static let shared = ExtensionManager()

    public let storage: ExtensionStorage
    public let permissions: PermissionManager
    public let hostManager: ExtensionHostManager
    public let packageService: PackageService
    public let diagnostics: DiagnosticsService

    public private(set) var installed: [InstalledExtension] = []
    public private(set) var searchResults: [ExtensionMetadata] = []
    public private(set) var searchError: String?
    public private(set) var isSearching: Bool = false
    public private(set) var installingIDs: Set<String> = []
    public private(set) var updates: [ExtensionUpdateInfo] = []
    public private(set) var contributions: [String: ExtensionContribution] = [:]
    public private(set) var isReady: Bool = false
    public var settings: ExtensionSettings
    public var workspaceRoot: URL?

    public var workspaceBridge: WorkspaceBridge? {
        guard let workspaceRoot else { return nil }
        return WorkspaceBridge(root: workspaceRoot, permissions: permissions)
    }

    private var searchTask: Task<Void, Never>?
    private var lastSearchQuery: String?
    private var searchOffset: Int = 0
    private var didLoad = false

    public convenience init() {
        self.init(storage: ExtensionStorage())
    }

    public init(storage: ExtensionStorage) {
        self.storage = storage
        self.permissions = PermissionManager(storage: storage)
        // Capability approval UI (gap-closure misc): host-initiated
        // requests ask a person through the approval center. With
        // no presenter installed the center denies immediately, so
        // headless runs keep the old deny-by-default behaviour.
        self.permissions.promptHandler = { request in
            await ExtensionPermissionApprovalCenter.shared.ask(request)
        }
        self.hostManager = ExtensionHostManager(storage: storage, permissions: permissions)
        self.packageService = PackageService(storage: storage)
        self.diagnostics = DiagnosticsService.shared
        self.settings = storage.loadSettings()
        // Wire host-initiated requests to this manager's handler.
        hostManager.hostRequestHandler = { [weak self] extensionId, request in
            guard let self else { return .null }
            return try await self.handleHostRequest(extensionId: extensionId, request: request)
        }
        // The sort-lines command is available from app start (U-11:
        // the exact Legacy startup wiring was not in the files read;
        // registering it here is the faithful equivalent).
        XcodeCommandRegistry.shared.register(SortLinesCommand())
    }

    /// First-load disk work; later calls are no-ops. `init` does no IO
    /// so opening Extensions cannot freeze the app.
    public func ensureReady() async {
        guard !didLoad else { return }
        didLoad = true
        await Task.detached { [storage] in
            try? storage.ensureDirectories()
            storage.cleanStaleStaging()
        }.value
        refreshInstalled()
        isReady = true
    }

    public func saveSettings() {
        try? storage.saveSettings(settings)
    }

    public func setWorkspaceRoot(_ url: URL?) {
        workspaceRoot = url
    }

    /// Evaluation order per record, first match wins (spec §3.3):
    /// missing dir → `.unavailable`; disabled → `.disabled`; missing
    /// deps → `.missingDependencies`; host running → `.running`;
    /// compatibility report decides `.enabled` vs `.incompatible`.
    /// If the manifest cannot be parsed, the record is `.enabled`
    /// (lenient fallback — observed; D-12, kept, not silently fixed).
    /// A broken extension can never prevent launch: malformed records
    /// are marked `.unavailable` instead of throwing.
    public func refreshInstalled() {
        let records = storage.loadInstalled()
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var evaluated: [InstalledExtension] = []
        for var record in records {
            let installURL = URL(fileURLWithPath: record.installPath)
            guard FileManager.default.fileExists(atPath: installURL.path) else {
                record.state = .unavailable
                record.lastError = "Installed directory is missing."
                evaluated.append(record)
                continue
            }
            if !record.isEnabled {
                record.state = .disabled
                evaluated.append(record)
                continue
            }
            let missing = DependencyResolver.missingDependencies(for: record, installedByID: byID)
            if !missing.isEmpty {
                record.state = .missingDependencies
                record.lastError = "Missing dependencies: \(missing.joined(separator: ", "))."
                evaluated.append(record)
                continue
            }
            if hostManager.isRunning(extensionId: record.id) {
                record.state = .running
                evaluated.append(record)
                continue
            }
            let manifestURL = installURL.appendingPathComponent("extension/package.json")
            if let manifest = try? VSCodeManifestParser.parseFile(at: manifestURL) {
                let report = Compatibility.evaluate(manifest: manifest)
                if report.compatible {
                    record.state = .enabled
                    record.lastError = nil
                } else {
                    record.state = .incompatible
                    record.lastError = report.reasons.joined(separator: " ")
                }
            } else {
                record.state = .enabled // Lenient fallback (D-12).
            }
            evaluated.append(record)
        }
        installed = evaluated.sorted { $0.metadata.displayName < $1.metadata.displayName }
    }

    private func persistInstalled() {
        try? storage.saveInstalled(installed)
    }

    // MARK: - Search (debounced via task cancellation)

    public func search(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            lastSearchQuery = nil
            searchOffset = 0
            return
        }
        isSearching = true
        searchError = nil
        lastSearchQuery = trimmed
        searchOffset = 0
        searchTask = Task {
            do {
                let client = RegistryClient(settings: settings)
                let page = try await client.search(query: trimmed)
                guard !Task.isCancelled else { return }
                searchResults = page.results
                searchOffset = page.results.count
                isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                searchError = error.localizedDescription
                searchResults = []
                isSearching = false
            }
        }
    }

    /// Paginated: the offset accumulates across pages.
    public func loadMoreSearchResults() {
        guard let query = lastSearchQuery, !query.isEmpty else { return }
        let offset = searchOffset
        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            do {
                let client = RegistryClient(settings: settings)
                let page = try await client.search(query: query, offset: offset)
                guard !Task.isCancelled else { return }
                searchResults += page.results
                searchOffset = offset + page.results.count
                isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                searchError = error.localizedDescription
                isSearching = false
            }
        }
    }

    // MARK: - Install / uninstall / enable

    /// Resolve download URL → download VSIX to
    /// `staging/<id>-<UUID>.vsix` → atomic package install → record
    /// with `isEnabled: true`, capabilities `[]` (install does not
    /// populate capabilities from the manifest; grants are requested
    /// at runtime) → `refreshInstalled()`. Concurrent install of the
    /// same id is a no-op. Cancellation deletes the downloaded file
    /// and any staging dir; the previous installation is never
    /// touched on failure.
    public func install(metadata: ExtensionMetadata) async throws {
        let id = metadata.id
        guard !installingIDs.contains(id) else { return }
        installingIDs.insert(id)
        defer { installingIDs.remove(id) }
        let client = RegistryClient(settings: settings)
        let downloadURL = try await client.downloadURL(for: metadata)
        let stagingFile = storage.stagingDirectory
            .appendingPathComponent("\(id)-\(UUID().uuidString).vsix")
        do {
            try FileManager.default.createDirectory(at: storage.stagingDirectory,
                                                    withIntermediateDirectories: true)
            try await client.downloadVSIX(from: downloadURL, to: stagingFile)
            let installedPackage = try await Task.detached { [packageService] in
                try packageService.install(vsixURL: stagingFile, identity: metadata.identity)
            }.value
            try? FileManager.default.removeItem(at: stagingFile)
            let record = InstalledExtension(
                metadata: metadata, isEnabled: true, state: .installed,
                installPath: installedPackage.directory.path,
                dependencies: installedPackage.manifest.allDependencies,
                capabilities: [])
            installed.removeAll { $0.id == id }
            installed.append(record)
            persistInstalled()
            refreshInstalled()
        } catch {
            try? FileManager.default.removeItem(at: stagingFile)
            throw error
        }
    }

    /// Install from a local `.vsix` file (works offline through the
    /// same `packageService.install` path, spec §6.2).
    public func installLocalVSIX(at vsixURL: URL, identity: ExtensionIdentity) async throws {
        let id = identity.id
        guard !installingIDs.contains(id) else { return }
        installingIDs.insert(id)
        defer { installingIDs.remove(id) }
        let installedPackage = try await Task.detached { [packageService] in
            try packageService.install(vsixURL: vsixURL, identity: identity)
        }.value
        let record = InstalledExtension(
            metadata: installedPackage.manifest.metadata, isEnabled: true, state: .installed,
            installPath: installedPackage.directory.path,
            dependencies: installedPackage.manifest.allDependencies,
            capabilities: [])
        installed.removeAll { $0.id == id }
        installed.append(record)
        persistInstalled()
        refreshInstalled()
    }

    public func uninstall(extensionId: String) async {
        deactivate(extensionId: extensionId)
        permissions.revokeAll(for: extensionId)
        try? packageService.uninstall(extensionId: extensionId)
        installed.removeAll { $0.id == extensionId }
        persistInstalled()
    }

    /// Disabling deactivates the host first; then persist +
    /// `refreshInstalled()`. Enabling does not auto-activate.
    public func setEnabled(extensionId: String, enabled: Bool) {
        guard let index = installed.firstIndex(where: { $0.id == extensionId }) else { return }
        if !enabled { deactivate(extensionId: extensionId) }
        // Re-enabling clears a quarantine (Legacy
        // `SDKExtensionManager.clearQuarantine`): the user inspected
        // the problem and asked for another chance, so the extension
        // gets a fresh crash budget too.
        if enabled { hostManager.clearQuarantine(for: extensionId) }
        installed[index].isEnabled = enabled
        installed[index].updatedAt = Date()
        persistInstalled()
        refreshInstalled()
    }

    /// VS Code-kind records only; compares registry `details()` version
    /// against the installed version; failures are warnings per
    /// extension, never fatal.
    public func checkUpdates() async {
        let client = RegistryClient(settings: settings)
        var found: [ExtensionUpdateInfo] = []
        for record in installed where record.metadata.kind == .vscode {
            do {
                let latest = try await client.details(for: record.identity)
                guard let installedVersion = SemanticVersion(string: record.metadata.version),
                      let latestVersion = SemanticVersion(string: latest.version),
                      latestVersion > installedVersion else { continue }
                found.append(ExtensionUpdateInfo(installed: record, latest: latest))
            } catch {
                diagnostics.warning("Update check failed for '\(record.id)': \(error.localizedDescription)",
                                    extensionId: record.id)
            }
        }
        updates = found
    }

    // MARK: - Activate / deactivate / execute

    public func activate(extensionId: String) async throws -> ExtensionContribution {
        guard let record = installed.first(where: { $0.id == extensionId }) else {
            throw SwiftCodeExtensionError.notInstalled(extensionId)
        }
        guard record.isEnabled else { throw SwiftCodeExtensionError.disabled(extensionId) }
        guard record.state != .incompatible else {
            throw SwiftCodeExtensionError.incompatible(record.lastError ?? "Extension '\(extensionId)' is incompatible.")
        }
        switch record.metadata.kind {
        case .vscode:
            let contribution = try await hostManager.activate(installed: record, workspaceRoot: workspaceRoot,
                                                              settings: settings)
            contributions[extensionId] = contribution
            registerAssistCommands(for: record, contribution: contribution)
            refreshInstalled()
            return contribution
        case .native:
            guard let manifest = NativePluginRegistry.shared.manifests.first(
                where: { "swiftcode.\($0.id)" == extensionId || $0.id == extensionId }) else {
                throw SwiftCodeExtensionError.notInstalled(extensionId)
            }
            let contribution = NativePluginRegistry.shared.contribution(for: manifest)
            contributions[extensionId] = contribution
            return contribution
        case .xcodeCommand:
            // Returns a synthetic contribution listing ALL registered
            // Xcode command identifiers (not per-extension).
            let commands = XcodeCommandRegistry.shared.allIdentifiers.map {
                ExtensionContributionCommand(command: $0, title: $0)
            }
            let contribution = ExtensionContribution(commands: commands, outputLines: [
                "Xcode-compatible commands run against a source buffer; see the Xcode Compatibility section.",
            ])
            contributions[extensionId] = contribution
            return contribution
        }
    }

    /// Registers each of a `.vscode` extension's contribution
    /// commands with the assistant, so `use_extension` can call
    /// them (Legacy `ExtV2Manager.registerAssistCommands`, called
    /// from `activate` for `.vscode` kind). Registration requires
    /// the `.assistTools` grant; `AssistBridge.register` returns
    /// false (and logs) when it is not granted.
    private func registerAssistCommands(for record: InstalledExtension, contribution: ExtensionContribution) {
        for command in contribution.commands {
            let descriptor = AssistBridge.descriptor(for: command, extensionId: record.id)
            _ = AssistBridge.register(descriptor, permissions: permissions)
        }
    }

    public func deactivate(extensionId: String) {
        hostManager.deactivate(extensionId: extensionId)
        ProviderRegistry.shared.clear(for: extensionId)
        contributions.removeValue(forKey: extensionId)
        refreshInstalled()
    }

    /// Native handlers first; else ownership check (a command
    /// belonging to another extension is rejected); else host
    /// execution. Returns the result's string value or `""`.
    public func executeCommand(extensionId: String, command: String,
                               args: [JSONValue] = []) async throws -> String {
        guard let record = installed.first(where: { $0.id == extensionId }) else {
            throw SwiftCodeExtensionError.notInstalled(extensionId)
        }
        guard record.isEnabled else { throw SwiftCodeExtensionError.disabled(extensionId) }
        if let handler = NativePluginRegistry.handler(for: command) {
            let result = try await handler(args)
            return result.stringValue ?? ""
        }
        if let owner = hostManager.ownerOfCommand(command), owner != extensionId {
            throw SwiftCodeExtensionError.invalidRequest(
                "Command '\(command)' belongs to extension '\(owner)', not '\(extensionId)'.")
        }
        if !hostManager.isRunning(extensionId: extensionId) {
            _ = try await activate(extensionId: extensionId)
        }
        let result = try await hostManager.executeCommand(extensionId: extensionId, command: command, args: args)
        return result.stringValue ?? ""
    }

    public func registerSamplePlugin() {
        NativePluginRegistry.shared.register(SamplePlugin.self)
        let manifest = SamplePlugin.manifest
        let record = InstalledExtension(
            metadata: manifest.metadata, isEnabled: true, state: .enabled, installPath: "",
            dependencies: [], capabilities: manifest.capabilities)
        installed.removeAll { $0.id == record.id }
        installed.append(record)
        persistInstalled()
        refreshInstalled()
    }

    // MARK: - Host-initiated requests (spec §4.3)

    /// `host.log` → diagnostics; `host.readFile` / `host.writeFile` →
    /// workspace bridge (capability-gated; no workspace open → invalid
    /// request); `host.applyEdit` → `{path, edits: [...]}` via the
    /// editor bridge (D-9 shape); `host.publishDiagnostics` → provider
    /// registry (malformed entries without a `message` are dropped);
    /// `host.registerCompletionProvider` / `host.registerHoverProvider`
    /// → provider registry by language; `host.requestPermission` →
    /// permission manager prompt, returns bool; `host.showQuickPick` /
    /// `host.showInputBox` → null (no picker UI attached on the host
    /// path; null is an honest "no selection", logged); every other
    /// allowed method → null (accepted, no action).
    public func handleHostRequest(extensionId: String, request: RPCRequest) async throws -> JSONValue {
        let params = request.params?.objectValue ?? [:]
        switch request.method {
        case "host.log":
            let message = params["message"]?.stringValue ?? ""
            diagnostics.info(message, extensionId: extensionId)
            return .null
        case "host.readFile", "host.writeFile":
            guard let bridge = workspaceBridge else {
                throw SwiftCodeExtensionError.invalidRequest("No workspace is open.")
            }
            let path = params["path"]?.stringValue ?? params["relativePath"]?.stringValue ?? ""
            if request.method == "host.readFile" {
                return .string(try bridge.readFile(relativePath: path, extensionId: extensionId))
            } else {
                let content = params["content"]?.stringValue ?? ""
                try bridge.writeFile(relativePath: path, content: content, extensionId: extensionId)
                return .bool(true)
            }
        case "host.applyEdit":
            guard let bridge = workspaceBridge else {
                throw SwiftCodeExtensionError.invalidRequest("No workspace is open.")
            }
            guard let path = params["path"]?.stringValue,
                  let rawEdits = params["edits"]?.arrayValue else {
                throw SwiftCodeExtensionError.invalidRequest("Invalid applyEdit request.")
            }
            var edits: [TextEdit] = []
            for rawEdit in rawEdits {
                guard let editObject = rawEdit.objectValue,
                      let rangeObject = editObject["range"]?.objectValue,
                      let startObject = rangeObject["start"]?.objectValue,
                      let endObject = rangeObject["end"]?.objectValue,
                      let startLine = startObject["line"]?.intValue,
                      let startCharacter = startObject["character"]?.intValue,
                      let endLine = endObject["line"]?.intValue,
                      let endCharacter = endObject["character"]?.intValue,
                      let newText = editObject["newText"]?.stringValue else {
                    throw SwiftCodeExtensionError.invalidRequest("Invalid applyEdit request.")
                }
                edits.append(TextEdit(
                    range: TextRange(start: TextPosition(line: startLine, character: startCharacter),
                                     end: TextPosition(line: endLine, character: endCharacter)),
                    newText: newText))
            }
            let current = try bridge.readFile(relativePath: path, extensionId: extensionId)
            let updated = try EditorBridge.applyEdits(edits, to: current)
            try bridge.writeFile(relativePath: path, content: updated, extensionId: extensionId)
            return .bool(true)
        case "host.publishDiagnostics":
            let path = params["path"]?.stringValue ?? params["relativePath"]?.stringValue ?? ""
            var published: [ExtensionDiagnostic] = []
            for raw in params["diagnostics"]?.arrayValue ?? [] {
                guard let entry = raw.objectValue,
                      let message = entry["message"]?.stringValue,
                      let rangeObject = entry["range"]?.objectValue,
                      let startObject = rangeObject["start"]?.objectValue,
                      let endObject = rangeObject["end"]?.objectValue,
                      let startLine = startObject["line"]?.intValue,
                      let startCharacter = startObject["character"]?.intValue,
                      let endLine = endObject["line"]?.intValue,
                      let endCharacter = endObject["character"]?.intValue else {
                    continue // Malformed entries without a message are dropped.
                }
                published.append(ExtensionDiagnostic(
                    relativePath: path,
                    range: TextRange(start: TextPosition(line: startLine, character: startCharacter),
                                     end: TextPosition(line: endLine, character: endCharacter)),
                    message: message,
                    severity: entry["severity"]?.stringValue ?? "Error",
                    source: extensionId))
            }
            ProviderRegistry.shared.publishDiagnostics(extensionId: extensionId, relativePath: path,
                                                       diagnostics: published)
            return .null
        case "host.registerCompletionProvider", "host.registerHoverProvider":
            let languages = params["language"]?.stringValue.map { [$0] }
                ?? params["languages"]?.arrayValue?.compactMap { $0.stringValue }
                ?? []
            for language in languages {
                if request.method == "host.registerCompletionProvider" {
                    ProviderRegistry.shared.registerCompletionProvider(extensionId: extensionId, language: language)
                } else {
                    ProviderRegistry.shared.registerHoverProvider(extensionId: extensionId, language: language)
                }
            }
            return .null
        case "host.requestPermission":
            guard let rawCapability = params["capability"]?.stringValue,
                  let capability = ExtensionCapability(rawValue: rawCapability) else {
                throw SwiftCodeExtensionError.invalidRequest("Invalid requestPermission request.")
            }
            let reason = params["reason"]?.stringValue ?? ""
            let granted = await permissions.request(extensionId: extensionId, capability: capability, reason: reason)
            return .bool(granted)
        case "host.showQuickPick", "host.showInputBox":
            diagnostics.info("\(request.method) has no picker UI attached; returning no selection.",
                             extensionId: extensionId)
            return .null
        default:
            return .null // Every other allowed method: accepted, no action.
        }
    }
}
