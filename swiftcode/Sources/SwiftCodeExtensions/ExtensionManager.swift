import Foundation

@MainActor
public final class ExtensionManager: ObservableObject {
    public static let shared = ExtensionManager()

    public let storage: ExtensionStorage
    public let permissions: PermissionManager
    public let hostManager: ExtensionHostManager
    public let packageService: PackageService
    public let diagnostics: DiagnosticsService

    @Published public private(set) var installed: [InstalledExtension] = []
    @Published public private(set) var searchResults: [ExtensionMetadata] = []
    @Published public private(set) var searchError: String?
    @Published public private(set) var isSearching: Bool = false
    @Published public private(set) var installingIDs: Set<String> = []
    @Published public private(set) var updates: [ExtensionUpdateInfo] = []
    @Published public private(set) var contributions: [String: ExtensionContribution] = [:]
    @Published public private(set) var isReady: Bool = false
    @Published public var settings: ExtensionSettings
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
        self.permissions.promptHandler = { request in
            await ExtensionPermissionApprovalCenter.shared.ask(request)
        }
        self.hostManager = ExtensionHostManager(storage: storage, permissions: permissions)
        self.packageService = PackageService(storage: storage)
        self.diagnostics = DiagnosticsService.shared
        self.settings = storage.loadSettings()
        hostManager.hostRequestHandler = { [weak self] extensionId, request in
            guard let self else { return .null }
            return try await self.handleHostRequest(extensionId: extensionId, request: request)
        }
        XcodeCommandRegistry.shared.register(SortLinesCommand())
    }

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
                record.state = .enabled
            }
            evaluated.append(record)
        }
        installed = evaluated.sorted { $0.metadata.displayName < $1.metadata.displayName }
    }

    private func persistInstalled() {
        try? storage.saveInstalled(installed)
    }

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

    public func setEnabled(extensionId: String, enabled: Bool) {
        guard let index = installed.firstIndex(where: { $0.id == extensionId }) else { return }
        if !enabled { deactivate(extensionId: extensionId) }
        if enabled { hostManager.clearQuarantine(for: extensionId) }
        installed[index].isEnabled = enabled
        installed[index].updatedAt = Date()
        persistInstalled()
        refreshInstalled()
    }

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
                    continue
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
            return .null
        }
    }
}

struct ExtensionManifest: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var version: String
    var description: String
    var author: String
    var category: ExtensionCategory
    var capabilities: [ExtensionCapability]
    var entryPoint: String
    var assetPaths: [String]
    var isInstalled: Bool
    var isEnabled: Bool
    var isUserCreated: Bool
    var isDownloaded: Bool = true
    var use_test_tools: Bool = false
    var swiftCodeAssistCapable: Bool = false
    var identificationTags: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, name, version, description, author, category, capabilities, entryPoint, assetPaths, isInstalled, isEnabled, isUserCreated, isDownloaded, use_test_tools, swiftCodeAssistCapable, identificationTags
    }

    init(
        id: String,
        name: String,
        version: String,
        description: String,
        author: String,
        category: ExtensionCategory,
        capabilities: [ExtensionCapability],
        entryPoint: String,
        assetPaths: [String],
        isInstalled: Bool,
        isEnabled: Bool,
        isUserCreated: Bool,
        isDownloaded: Bool = true,
        use_test_tools: Bool = false,
        swiftCodeAssistCapable: Bool = false,
        identificationTags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.category = category
        self.capabilities = capabilities
        self.entryPoint = entryPoint
        self.assetPaths = assetPaths
        self.isInstalled = isInstalled
        self.isEnabled = isEnabled
        self.isUserCreated = isUserCreated
        self.isDownloaded = isDownloaded
        self.use_test_tools = use_test_tools
        self.swiftCodeAssistCapable = swiftCodeAssistCapable
        self.identificationTags = identificationTags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        description = try container.decode(String.self, forKey: .description)
        author = try container.decode(String.self, forKey: .author)
        category = try container.decode(ExtensionCategory.self, forKey: .category)
        capabilities = try container.decode([ExtensionCapability].self, forKey: .capabilities)
        entryPoint = try container.decode(String.self, forKey: .entryPoint)
        assetPaths = try container.decode([String].self, forKey: .assetPaths)
        isInstalled = try container.decode(Bool.self, forKey: .isInstalled)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isUserCreated = try container.decode(Bool.self, forKey: .isUserCreated)
        isDownloaded = try container.decodeIfPresent(Bool.self, forKey: .isDownloaded) ?? true
        use_test_tools = try container.decodeIfPresent(Bool.self, forKey: .use_test_tools) ?? false
        swiftCodeAssistCapable = try container.decodeIfPresent(Bool.self, forKey: .swiftCodeAssistCapable) ?? false
        identificationTags = try container.decodeIfPresent([String].self, forKey: .identificationTags) ?? []
    }

    enum ExtensionCategory: String, Codable, CaseIterable, Identifiable {
        case editor        = "Editor"
        case tools         = "Tools"
        case themes        = "Themes"
        case languages     = "Languages"
        case ai            = "AI"
        case build         = "Build"
        case testing       = "Testing"
        case other         = "Other"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .editor:    return "pencil.and.outline"
            case .tools:     return "wrench.and.screwdriver"
            case .themes:    return "paintpalette"
            case .languages: return "chevron.left.forwardslash.chevron.right"
            case .ai:        return "cpu"
            case .build:     return "hammer"
            case .testing:   return "checkmark.shield"
            case .other:     return "puzzlepiece.extension"
            }
        }
    }

    enum ExtensionCapability: String, Codable, CaseIterable {
        case codeCompletion   = "Code Completion"
        case syntaxHighlight  = "Syntax Highlight"
        case formatter        = "Formatter"
        case linter           = "Linter"
        case fileTemplate     = "File Template"
        case command          = "Command"
        case buildTool        = "Build Tool"
        case aiAssistant      = "AI Assistant"
        case themeProvider    = "Theme Provider"
        case languageSupport  = "Language Support"
    }
}
