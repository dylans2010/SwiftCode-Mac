import Foundation

// MARK: - Plugin Manifest

struct PluginToolBinding: Codable, Hashable {
    var toolID: String
    var usageDescription: String
    var isRequired: Bool
}

struct PluginAutomationStep: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var instruction: String
    var expectedOutput: String
}

struct PluginConfigField: Codable, Hashable, Identifiable {
    enum FieldType: String, Codable, CaseIterable {
        case string
        case number
        case boolean
        case list
    }

    var id: UUID = UUID()
    var key: String
    var title: String
    var type: FieldType
    var defaultValue: String
    var isRequired: Bool
}

struct PluginManifest: Identifiable, Codable {
    var id: String
    var name: String
    var version: String
    var description: String
    var author: String
    var entryPoint: String
    var capabilities: [Capability]
    var isEnabled: Bool = true

    // Advanced plugin metadata
    var tags: [String] = []
    var minimumSwiftCodeVersion: String = "1.0.0"
    var toolBindings: [PluginToolBinding] = []
    var automationSteps: [PluginAutomationStep] = []
    var configurationSchema: [PluginConfigField] = []

    enum Capability: String, Codable, CaseIterable {
        case codeCompletion
        case syntaxHighlight
        case buildTool
        case formatter
        case linter
        case fileTemplate
        case command
        case toolOrchestration
        case workspaceAutomation
        case contextualReasoning
    }

    enum CodingKeys: String, CodingKey {
        case id, name, version, description, author, entryPoint, capabilities, isEnabled
        case tags, minimumSwiftCodeVersion, toolBindings, automationSteps, configurationSchema
    }

    init(id: String,
         name: String,
         version: String,
         description: String,
         author: String,
         entryPoint: String,
         capabilities: [Capability],
         isEnabled: Bool = true,
         tags: [String] = [],
         minimumSwiftCodeVersion: String = "1.0.0",
         toolBindings: [PluginToolBinding] = [],
         automationSteps: [PluginAutomationStep] = [],
         configurationSchema: [PluginConfigField] = []) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.entryPoint = entryPoint
        self.capabilities = capabilities
        self.isEnabled = isEnabled
        self.tags = tags
        self.minimumSwiftCodeVersion = minimumSwiftCodeVersion
        self.toolBindings = toolBindings
        self.automationSteps = automationSteps
        self.configurationSchema = configurationSchema
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        description = try container.decode(String.self, forKey: .description)
        author = try container.decode(String.self, forKey: .author)
        entryPoint = try container.decode(String.self, forKey: .entryPoint)
        capabilities = try container.decode([Capability].self, forKey: .capabilities)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        minimumSwiftCodeVersion = try container.decodeIfPresent(String.self, forKey: .minimumSwiftCodeVersion) ?? "1.0.0"
        toolBindings = try container.decodeIfPresent([PluginToolBinding].self, forKey: .toolBindings) ?? []
        automationSteps = try container.decodeIfPresent([PluginAutomationStep].self, forKey: .automationSteps) ?? []
        configurationSchema = try container.decodeIfPresent([PluginConfigField].self, forKey: .configurationSchema) ?? []
    }
}

// MARK: - Plugin Manager

@MainActor
final class PluginManager: ObservableObject {
    static let shared = PluginManager()

    @Published var plugins: [PluginManifest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var pluginsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plugins")
    }

    private init() {
        ensurePluginsDirectory()
        Task { await scanPlugins() }
    }

    private func ensurePluginsDirectory() {
        try? FileManager.default.createDirectory(
            at: pluginsDirectory, withIntermediateDirectories: true
        )
    }

    func scanPlugins() async {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return }

        var found: [PluginManifest] = []
        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let manifestURL = url.appendingPathComponent("plugin.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  var manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else { continue }

            manifest.isEnabled = loadEnabledState(for: manifest.id)
            found.append(manifest)
        }

        plugins = found.sorted { $0.name < $1.name }
    }

    func togglePlugin(_ plugin: PluginManifest) {
        guard let idx = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        plugins[idx].isEnabled.toggle()
        saveEnabledState(for: plugins[idx].id, enabled: plugins[idx].isEnabled)
    }

    func installPlugin(from sourceURL: URL) throws {
        let destURL = pluginsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        Task { await scanPlugins() }
    }

    func uninstallPlugin(_ plugin: PluginManifest) throws {
        let pluginURL = pluginsDirectory.appendingPathComponent(plugin.id)
        try FileManager.default.removeItem(at: pluginURL)
        plugins.removeAll { $0.id == plugin.id }
    }

    func plugins(with capability: PluginManifest.Capability) -> [PluginManifest] {
        plugins.filter { $0.isEnabled && $0.capabilities.contains(capability) }
    }

    func toolAwarePlugins(for toolID: String) -> [PluginManifest] {
        plugins.filter {
            $0.isEnabled && $0.toolBindings.contains(where: { $0.toolID == toolID })
        }
    }

    func createPlugin(manifest: PluginManifest, mainCode: String) throws {
        let pluginURL = pluginsDirectory.appendingPathComponent(manifest.id)
        let fm = FileManager.default

        try fm.createDirectory(at: pluginURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: pluginURL.appendingPathComponent("plugin.json"))

        try mainCode.write(
            to: pluginURL.appendingPathComponent(manifest.entryPoint),
            atomically: true,
            encoding: .utf8
        )

        Task { await scanPlugins() }
    }

    func isPluginCompatible(_ manifest: PluginManifest) -> Bool {
        if #available(iOS 17.0, *) {
            return true
        } else if #available(iOS 16.0, *) {
            let isAIPlugin = manifest.capabilities.contains(.codeCompletion) || manifest.name.lowercased().contains("ai")
            return !isAIPlugin
        } else {
            let basicCapabilities: Set<PluginManifest.Capability> = [.syntaxHighlight, .formatter]
            return manifest.capabilities.allSatisfy { basicCapabilities.contains($0) }
        }
    }

    private static let enabledKey = "com.swiftcode.plugins.enabled"

    private func saveEnabledState(for id: String, enabled: Bool) {
        var states = loadAllEnabledStates()
        states[id] = enabled
        UserDefaults.standard.set(states, forKey: Self.enabledKey)
    }

    private func loadEnabledState(for id: String) -> Bool {
        loadAllEnabledStates()[id] ?? true
    }

    private func loadAllEnabledStates() -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: Self.enabledKey) as? [String: Bool] ?? [:]
    }
}
