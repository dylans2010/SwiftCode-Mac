import Foundation

// MARK: - Extension Manifest

/// Represents the metadata and configuration for a SwiftCode Extension.
struct ExtensionManifest: Identifiable, Codable, Equatable {
    var id: String                      // Unique identifier (folder name)
    var name: String
    var version: String
    var description: String
    var author: String
    var category: ExtensionCategory
    var capabilities: [ExtensionCapability]
    var entryPoint: String              // Relative path to the main Swift file
    var assetPaths: [String]            // Relative paths to asset files
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

// MARK: - Extension Manager

/// Manages all Extensions in SwiftCode: scanning, installing, enabling, disabling,
/// creating, and deleting. Extensions are stored in the app's Documents/Extensions
/// folder and load dynamically into the IDE when installed.
@MainActor
final class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()

    @Published var extensions: [ExtensionManifest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Root directory for all user-created and installed extensions.
    var extensionsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Extensions")
    }

    private init() {
        ensureExtensionsDirectory()
        seedBuiltInExtensions()
        Task { await scanExtensions() }
    }

    /// Fetches all available extensions (both installed and remote placeholders).
    /// In a real app, this might fetch from a remote API. For now, it combines
    /// local extensions with potential remote ones.
    func getAllAvailableExtensions() -> [ExtensionManifest] {
        // This would typically merge locally scanned extensions with a remote registry.
        // For this task, we'll ensure the `extensions` array represents all of them.
        return extensions
    }

    // MARK: - Built-in Extensions

    private var builtInManifests: [ExtensionManifest] {
        [
            ExtensionManifest(id: "swiftformatter", name: "Swift Formatter", version: "1.0.0",
                description: "Automatically format Swift code on save using SwiftFormat rules.",
                author: "SwiftCode", category: .editor,
                capabilities: [.formatter], entryPoint: "SwiftFormatterExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "swiftlintrunner", name: "SwiftLint Runner", version: "1.0.0",
                description: "Run SwiftLint inline and surface warnings/errors in the editor gutter.",
                author: "SwiftCode", category: .tools,
                capabilities: [.linter], entryPoint: "SwiftLintRunnerExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "gitblame", name: "Git Blame", version: "1.0.0",
                description: "Show inline git blame annotations for each line of code.",
                author: "SwiftCode", category: .tools,
                capabilities: [.command], entryPoint: "GitBlameExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "colorpicker", name: "Color Picker", version: "1.0.0",
                description: "Inline color swatches and a picker for UIColor/SwiftUI Color literals.",
                author: "SwiftCode", category: .editor,
                capabilities: [.command], entryPoint: "ColorPickerExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "snippetlibrary", name: "Snippet Library", version: "1.0.0",
                description: "Manage and insert reusable code snippets with tab-expansion.",
                author: "SwiftCode", category: .editor,
                capabilities: [.fileTemplate], entryPoint: "SnippetLibraryExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "markdownpreview", name: "Markdown Preview", version: "1.0.0",
                description: "Live side-by-side preview for Markdown files.",
                author: "SwiftCode", category: .editor,
                capabilities: [.syntaxHighlight], entryPoint: "MarkdownPreviewExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "jsonformatter", name: "JSON Formatter", version: "1.0.0",
                description: "Pretty-print and validate JSON files with collapsible nodes.",
                author: "SwiftCode", category: .editor,
                capabilities: [.formatter], entryPoint: "JSONFormatterExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "regextester", name: "Regex Tester", version: "1.0.0",
                description: "Test regular expressions interactively with match highlighting.",
                author: "SwiftCode", category: .tools,
                capabilities: [.command], entryPoint: "RegexTesterExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "darkprotheme", name: "Dark Pro Theme", version: "1.0.0",
                description: "A professional dark theme inspired by VS Code Dark+.",
                author: "SwiftCode", category: .themes,
                capabilities: [.themeProvider], entryPoint: "DarkProThemeExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: false, isUserCreated: false),

            ExtensionManifest(id: "nordtheme", name: "Nord Theme", version: "1.0.0",
                description: "The popular Nord arctic color palette for comfortable night coding.",
                author: "SwiftCode", category: .themes,
                capabilities: [.themeProvider], entryPoint: "NordThemeExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: false, isUserCreated: false),

            ExtensionManifest(id: "gruvboxtheme", name: "Gruvbox Theme", version: "1.0.0",
                description: "Retro groove color scheme with warm tones.",
                author: "SwiftCode", category: .themes,
                capabilities: [.themeProvider], entryPoint: "GruvboxThemeExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: false, isUserCreated: false),

            ExtensionManifest(id: "kotlinsupport", name: "Kotlin Support", version: "1.0.0",
                description: "Syntax highlighting and basic IntelliSense for Kotlin files.",
                author: "SwiftCode", category: .languages,
                capabilities: [.languageSupport, .syntaxHighlight], entryPoint: "KotlinSupportExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "typescriptsupport", name: "TypeScript Support", version: "1.0.0",
                description: "TypeScript and TSX syntax highlighting with type annotations.",
                author: "SwiftCode", category: .languages,
                capabilities: [.languageSupport, .syntaxHighlight], entryPoint: "TypeScriptSupportExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "pythonsupport", name: "Python Support", version: "1.0.0",
                description: "Python 3 syntax highlighting, docstring templates, and snippet library.",
                author: "SwiftCode", category: .languages,
                capabilities: [.languageSupport, .syntaxHighlight, .fileTemplate], entryPoint: "PythonSupportExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "rustsupport", name: "Rust Support", version: "1.0.0",
                description: "Rust syntax highlighting with ownership and lifetime hints.",
                author: "SwiftCode", category: .languages,
                capabilities: [.languageSupport, .syntaxHighlight], entryPoint: "RustSupportExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "gosupport", name: "Go Support", version: "1.0.0",
                description: "Go syntax highlighting and gofmt integration.",
                author: "SwiftCode", category: .languages,
                capabilities: [.languageSupport, .syntaxHighlight, .formatter], entryPoint: "GoSupportExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "aidocgen", name: "AI Doc Generator", version: "1.0.0",
                description: "Auto-generate Swift DocC documentation comments using AI.",
                author: "SwiftCode", category: .ai,
                capabilities: [.aiAssistant], entryPoint: "AIDocGenExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "airefactor", name: "AI Refactor", version: "1.0.0",
                description: "AI-powered refactoring suggestions: extract method, rename, restructure.",
                author: "SwiftCode", category: .ai,
                capabilities: [.aiAssistant], entryPoint: "AIRefactorExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "unittestgen", name: "Unit Test Generator", version: "1.0.0",
                description: "Generate XCTest unit tests for selected functions using AI.",
                author: "SwiftCode", category: .testing,
                capabilities: [.aiAssistant], entryPoint: "UnitTestGenExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "xcodebuildtool", name: "Xcode Build Tool", version: "1.0.0",
                description: "Trigger xcodebuild commands and stream build logs to the console.",
                author: "SwiftCode", category: .build,
                capabilities: [.buildTool], entryPoint: "XcodeBuildToolExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "swiftpackagemanager", name: "Swift Package Manager", version: "1.0.0",
                description: "Manage SPM dependencies: add, update, remove packages graphically.",
                author: "SwiftCode", category: .build,
                capabilities: [.buildTool], entryPoint: "SwiftPackageManagerExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "doccgenerator", name: "DocC Generator", version: "1.0.0",
                description: "Build and preview Apple DocC documentation directly in the IDE.",
                author: "SwiftCode", category: .tools,
                capabilities: [.command], entryPoint: "DocCGeneratorExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "todohighlighter", name: "TODO Highlighter", version: "1.0.0",
                description: "Highlight TODO, FIXME, MARK and HACK comments with color badges.",
                author: "SwiftCode", category: .editor,
                capabilities: [.syntaxHighlight], entryPoint: "TodoHighlighterExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "multicursor", name: "Multi-Cursor", version: "1.0.0",
                description: "Edit multiple locations simultaneously with multi-cursor support.",
                author: "SwiftCode", category: .editor,
                capabilities: [.command], entryPoint: "MultiCursorExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),

            ExtensionManifest(id: "codestats", name: "Code Stats", version: "1.0.0",
                description: "Display line counts, complexity metrics, and language breakdown.",
                author: "SwiftCode", category: .tools,
                capabilities: [.command], entryPoint: "CodeStatsExtensionView.swift",
                assetPaths: [], isInstalled: true, isEnabled: true, isUserCreated: false),
        ]
    }

    /// Seeds built-in extensions into the Documents/Extensions folder on first launch.
    /// Built-in extension folders are skipped individually if they already exist.
    func seedBuiltInExtensions() {
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for manifest in builtInManifests {
            let folderURL = extensionsDirectory.appendingPathComponent(manifest.id)
            guard !fm.fileExists(atPath: folderURL.path) else { continue }
            do {
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                let data = try encoder.encode(manifest)
                try data.write(to: folderURL.appendingPathComponent("extension.json"))
                let placeholder = "// \(manifest.name) Extension Entry Point\n// Category: \(manifest.category.rawValue)\n"
                try placeholder.write(
                    to: folderURL.appendingPathComponent(manifest.entryPoint),
                    atomically: true, encoding: .utf8
                )
            } catch {
                print("[ExtensionManager] Failed to seed \(manifest.id): \(error)")
            }
        }
    }

    private func ensureExtensionsDirectory() {
        try? FileManager.default.createDirectory(
            at: extensionsDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Scan

    /// Scans the Extensions directory for installed extension manifests.
    func scanExtensions() async {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: extensionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            // If directory listing fails, just show built-ins as not downloaded
            self.extensions = builtInManifests.map {
                var m = $0
                m.isDownloaded = false
                m.isInstalled = false
                m.isEnabled = false
                return m
            }
            return
        }

        var found: [ExtensionManifest] = []
        let localIds = contents.map { $0.lastPathComponent }

        // Add built-ins, checking if they are locally present
        for var manifest in builtInManifests {
            if localIds.contains(manifest.id) {
                let manifestURL = extensionsDirectory.appendingPathComponent(manifest.id).appendingPathComponent("extension.json")
                if let data = try? Data(contentsOf: manifestURL),
                   let decoded = try? JSONDecoder().decode(ExtensionManifest.self, from: data) {
                    manifest = decoded
                }
                manifest.isDownloaded = true
                manifest.isInstalled = true
                manifest.isEnabled = loadEnabledState(for: manifest.id)
            } else {
                manifest.isDownloaded = false
                manifest.isInstalled = false
                manifest.isEnabled = false
            }
            found.append(manifest)
        }

        // Add any other local extensions that are not built-in
        for url in contents {
            let id = url.lastPathComponent
            if !builtInManifests.contains(where: { $0.id == id }) {
                let manifestURL = url.appendingPathComponent("extension.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      var manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data) else { continue }
                manifest.isDownloaded = true
                manifest.isInstalled = true
                manifest.isEnabled = loadEnabledState(for: manifest.id)
                found.append(manifest)
            }
        }

        extensions = found.sorted { $0.name < $1.name }
    }

    // MARK: - Download Extension

    /// Marks an extension as downloaded, making it available for use.
    func downloadExtension(_ ext: ExtensionManifest) {
        guard let idx = extensions.firstIndex(where: { $0.id == ext.id }) else { return }
        // Simulate download delay
        isLoading = true
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                self.extensions[idx].isDownloaded = true
                self.extensions[idx].isInstalled = true
                self.extensions[idx].isEnabled = true
                self.saveEnabledState(for: self.extensions[idx].id, enabled: true)
                self.isLoading = false
            }
        }
    }

    /// Downloads all extensions at once.
    func downloadAllExtensions() {
        for i in extensions.indices {
            extensions[i].isDownloaded = true
            extensions[i].isInstalled = true
            extensions[i].isEnabled = true
            saveEnabledState(for: extensions[i].id, enabled: true)
        }
    }

    // MARK: - Enable / Disable

    func toggleExtension(_ ext: ExtensionManifest) {
        guard let idx = extensions.firstIndex(where: { $0.id == ext.id }) else { return }
        extensions[idx].isEnabled.toggle()
        saveEnabledState(for: extensions[idx].id, enabled: extensions[idx].isEnabled)

        // Handle use_test_tools if enabled for this extension
        if extensions[idx].isEnabled && extensions[idx].use_test_tools {
            Task {
                await TestToolsManager.shared.runExtensionTests(extensionID: extensions[idx].id)
            }
        }

        // PLACEHOLDER: Notify the IDE to load or unload this extension's entry point.
        // IDEExtensionLoader.shared.reload(extensions[idx])

        AssistCapabilityExecutor.executeIfNeeded(
            kind: AssistCapabilityKind.`extension`,
            name: extensions[idx].name,
            identifiers: extensions[idx].identificationTags,
            payload: [
                "extensionID": extensions[idx].id,
                "enabled": "\(extensions[idx].isEnabled)"
            ]
        )
    }

    // MARK: - Install

    /// Installs an extension from a source directory.
    func installExtension(from sourceURL: URL) throws {
        let destURL = extensionsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        Task { await scanExtensions() }
    }

    // MARK: - Uninstall / Delete

    /// Safely removes an extension folder and removes it from the IDE.
    func uninstallExtension(_ ext: ExtensionManifest) throws {
        let extURL = extensionsDirectory.appendingPathComponent(ext.id)
        if FileManager.default.fileExists(atPath: extURL.path) {
            try FileManager.default.removeItem(at: extURL)
        }
        extensions.removeAll { $0.id == ext.id }
        // PLACEHOLDER: Notify the IDE to unload this extension.
        // IDEExtensionLoader.shared.unload(ext)
    }

    // MARK: - Create User Extension

    /// Creates a new user-created extension under the Extensions directory.
    /// Returns the folder URL of the created extension.
    @discardableResult
    func createExtension(manifest: ExtensionManifest, swiftFiles: [(name: String, content: String)], assetFiles: [(name: String, data: Data)]) throws -> URL {
        let folderURL = extensionsDirectory.appendingPathComponent(manifest.id)
        let fm = FileManager.default

        // Create the extension folder
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // Save the manifest
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: folderURL.appendingPathComponent("extension.json"))

        // Save Swift source files
        for file in swiftFiles {
            let fileURL = folderURL.appendingPathComponent(file.name)
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Save asset files
        let assetsFolder = folderURL.appendingPathComponent("Assets")
        if !assetFiles.isEmpty {
            try fm.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
            for asset in assetFiles {
                try asset.data.write(to: assetsFolder.appendingPathComponent(asset.name))
            }
        }

        Task { await scanExtensions() }
        AssistCapabilityExecutor.executeIfNeeded(
            kind: AssistCapabilityKind.`extension`,
            name: manifest.name,
            identifiers: manifest.identificationTags,
            payload: ["extensionID": manifest.id, "event": "create"]
        )
        return folderURL
    }

    // MARK: - Update Extension

    /// Updates an existing extension's manifest and optionally its files.
    func updateExtension(manifest: ExtensionManifest) throws {
        guard let idx = extensions.firstIndex(where: { $0.id == manifest.id }) else { return }
        extensions[idx] = manifest
        let folderURL = extensionsDirectory.appendingPathComponent(manifest.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: folderURL.appendingPathComponent("extension.json"))
        AssistCapabilityExecutor.executeIfNeeded(
            kind: AssistCapabilityKind.`extension`,
            name: manifest.name,
            identifiers: manifest.identificationTags,
            payload: ["extensionID": manifest.id, "event": "update"]
        )
    }

    // MARK: - Filter Helpers

    func extensions(with capability: ExtensionManifest.ExtensionCapability) -> [ExtensionManifest] {
        extensions.filter { $0.isEnabled && $0.capabilities.contains(capability) }
    }

    func extensions(inCategory category: ExtensionManifest.ExtensionCategory) -> [ExtensionManifest] {
        extensions.filter { $0.category == category }
    }

    // MARK: - Preferences Persistence

    private static let enabledKey = "com.swiftcode.extensions.enabled"

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
