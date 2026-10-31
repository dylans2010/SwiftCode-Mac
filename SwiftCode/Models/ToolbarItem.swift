import Foundation
import AppKit

// MARK: - Toolbar Item

struct ToolbarTool: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let icon: String
    let category: String
    var isEnabled: Bool
    var order: Int

    static func == (lhs: ToolbarTool, rhs: ToolbarTool) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toolbar Manager

@MainActor
final class ToolbarManager: ObservableObject {
    static let shared = ToolbarManager()

    @Published var tools: [ToolbarTool] = []

    private static let storageKey = "com.swiftcode.toolbarTools"

    private init() {
        loadTools()
    }

    var enabledTools: [ToolbarTool] {
        tools.filter(\.isEnabled).sorted { $0.order < $1.order }
    }

    func toggleTool(id: String) {
        if let idx = tools.firstIndex(where: { $0.id == id }) {
            tools[idx].isEnabled.toggle()
            persist()
        }
    }

    func toggleToolByNameOrID(_ identifier: String) {
        let clean = identifier.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "open_", with: "")
        if let idx = tools.firstIndex(where: { $0.id.lowercased() == clean || $0.id == identifier }) {
            tools[idx].isEnabled.toggle()
            persist()
            return
        }
        if let idx = tools.firstIndex(where: { $0.name.lowercased().contains(clean) || clean.contains($0.name.lowercased()) }) {
            tools[idx].isEnabled.toggle()
            persist()
            return
        }
    }

    func moveTool(from source: IndexSet, to destination: Int) {
        var enabled = enabledTools
        enabled.move(fromOffsets: source, toOffset: destination)
        for (i, tool) in enabled.enumerated() {
            if let idx = tools.firstIndex(where: { $0.id == tool.id }) {
                tools[idx].order = i
            }
        }
        persist()
    }

    func resetToDefaults() {
        tools = Self.defaultTools
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tools) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func loadTools() {
        let defaultMap = Dictionary(uniqueKeysWithValues: Self.defaultTools.map { ($0.id, $0) })

        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ToolbarTool].self, from: data) {
            // Keep user customization for supported tools only, and drop deprecated tools.
            var merged: [ToolbarTool] = []
            var seen = Set<String>()

            for tool in decoded where defaultMap[tool.id] != nil {
                merged.append(tool)
                seen.insert(tool.id)
            }

            for tool in Self.defaultTools where !seen.contains(tool.id) {
                merged.append(tool)
            }

            tools = merged
            persist()
        } else {
            tools = Self.defaultTools
        }
    }

    static let defaultTools: [ToolbarTool] = [
        ToolbarTool(id: "config_selector", name: "Build Configuration", icon: "gearshape", category: "Build Options", isEnabled: false, order: 0),
        ToolbarTool(id: "destination_selector", name: "Build Destination", icon: "macbook.and.iphone", category: "Build Options", isEnabled: false, order: 1),
        ToolbarTool(id: "code_search", name: "Code Search", icon: "magnifyingglass", category: "Navigation", isEnabled: false, order: 2),
        ToolbarTool(id: "errors_viewer", name: "Errors Viewer", icon: "exclamationmark.triangle.fill", category: "Diagnostics", isEnabled: false, order: 3),
        ToolbarTool(id: "dependency_manager", name: "Dependencies", icon: "shippingbox.fill", category: "Project", isEnabled: false, order: 4),
        ToolbarTool(id: "file_navigator", name: "File Navigator", icon: "folder.fill", category: "Navigation", isEnabled: false, order: 5),
        ToolbarTool(id: "build_trigger", name: "Build Shortcut", icon: "hammer.fill", category: "Build", isEnabled: false, order: 6),
        ToolbarTool(id: "command_palette", name: "Command Palette", icon: "terminal.fill", category: "Tools", isEnabled: false, order: 7),
        ToolbarTool(id: "go_to_line", name: "Go to Line", icon: "arrow.right.to.line", category: "Navigation", isEnabled: false, order: 8),
        ToolbarTool(id: "symbol_navigator", name: "Symbol Navigator", icon: "list.bullet.indent", category: "Navigation", isEnabled: false, order: 9),
        ToolbarTool(id: "github_actions", name: "GitHub Actions", icon: "arrow.triangle.2.circlepath.circle.fill", category: "Git", isEnabled: false, order: 10),
        ToolbarTool(id: "local_simulation", name: "Preview", icon: "play.display", category: "Build", isEnabled: false, order: 11),
        ToolbarTool(id: "collaboration", name: "Collaboration", icon: "person.2.badge.gearshape.fill", category: "Project", isEnabled: false, order: 12),

        ToolbarTool(id: "project_settings", name: "Project Settings", icon: "gearshape.fill", category: "Project", isEnabled: false, order: 13),
        ToolbarTool(id: "project_index", name: "Project Index", icon: "list.number", category: "Navigation", isEnabled: false, order: 11),
        ToolbarTool(id: "install_dependency", name: "Install Dependency", icon: "plus.square.fill", category: "Project", isEnabled: false, order: 12),
        ToolbarTool(id: "diff_viewer", name: "Diff Viewer", icon: "arrow.left.arrow.right", category: "Git", isEnabled: false, order: 13),
        ToolbarTool(id: "ai_code_gen", name: "AI Code Generation", icon: "wand.and.stars", category: "AI", isEnabled: false, order: 14),
        ToolbarTool(id: "build_status", name: "Build Status", icon: "chart.bar.fill", category: "Build", isEnabled: false, order: 15),
        ToolbarTool(id: "build_logs", name: "Build Logs", icon: "doc.text.magnifyingglass", category: "Build", isEnabled: false, order: 16),
        ToolbarTool(id: "minimap_settings", name: "Minimap Settings", icon: "map.fill", category: "Editor", isEnabled: false, order: 17),
        ToolbarTool(id: "project_analyzer", name: "Project Analyzer", icon: "waveform.path.ecg", category: "Diagnostics", isEnabled: false, order: 18),
        ToolbarTool(id: "sf_symbols_browser", name: "SF Symbols", icon: "square.grid.2x2.fill", category: "Tools", isEnabled: false, order: 19),
        ToolbarTool(id: "terminal", name: "Terminal", icon: "terminal", category: "Build", isEnabled: false, order: 20),
        ToolbarTool(id: "git_history", name: "Git History", icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", category: "Git", isEnabled: false, order: 21),
        ToolbarTool(id: "symbol_outline", name: "Symbol Outline", icon: "list.bullet.rectangle", category: "Navigation", isEnabled: false, order: 22),
        ToolbarTool(id: "plugin_manager", name: "Plugin Manager", icon: "puzzlepiece.extension.fill", category: "Tools", isEnabled: false, order: 23),
        ToolbarTool(id: "file_preview", name: "File Preview", icon: "eye.fill", category: "File", isEnabled: false, order: 24),
        ToolbarTool(id: "search_documentation", name: "Search Docs", icon: "doc.text.magnifyingglass", category: "AI", isEnabled: false, order: 25),
        ToolbarTool(id: "snippets_library", name: "Snippets Library", icon: "text.badge.plus", category: "Tools", isEnabled: false, order: 26),
        ToolbarTool(id: "code_refactoring", name: "Code Refactoring", icon: "wand.and.rays", category: "Editor", isEnabled: false, order: 27),
        ToolbarTool(id: "error_diagnostics", name: "Error Diagnostics", icon: "stethoscope", category: "Diagnostics", isEnabled: false, order: 28),
        ToolbarTool(id: "extension_marketplace", name: "Extension Marketplace", icon: "shippingbox.circle", category: "Tools", isEnabled: false, order: 29),
        ToolbarTool(id: "code_intelligence", name: "Code Intelligence", icon: "brain", category: "Editor", isEnabled: false, order: 30),
        ToolbarTool(id: "crash_log_analyzer", name: "Crash Analyzer", icon: "ant", category: "Diagnostics", isEnabled: false, order: 31),
        ToolbarTool(id: "project_dependency_graph", name: "Dependency Graph", icon: "point.3.connected.trianglepath.dotted", category: "Navigation", isEnabled: false, order: 32),
        ToolbarTool(id: "symbol_index", name: "Symbol Index", icon: "text.magnifyingglass", category: "Navigation", isEnabled: false, order: 33),
        ToolbarTool(id: "code_metrics", name: "Code Metrics", icon: "chart.xyaxis.line", category: "Diagnostics", isEnabled: false, order: 34),
        ToolbarTool(id: "documentation_browser", name: "Docs Browser", icon: "book", category: "Tools", isEnabled: false, order: 35),
        ToolbarTool(id: "workspace_profiles", name: "Workspace Profiles", icon: "person.2.crop.square.stack", category: "Project", isEnabled: false, order: 36),
        ToolbarTool(id: "asset_manager", name: "Asset Manager", icon: "photo.stack", category: "File", isEnabled: false, order: 37),
        ToolbarTool(id: "debug_tools", name: "Debug Tools", icon: "ladybug.fill", category: "Diagnostics", isEnabled: false, order: 38),
        ToolbarTool(id: "deployments", name: "Deployments", icon: "cloud.fill", category: "Tools", isEnabled: false, order: 39),
        ToolbarTool(id: "run_tests", name: "Run Tests", icon: "play.shield.fill", category: "Diagnostics", isEnabled: false, order: 40),
        ToolbarTool(id: "gist_manager", name: "Gist Manager", icon: "tray.full.fill", category: "Git", isEnabled: false, order: 41),
        ToolbarTool(id: "assist_view", name: "Assist", icon: "sparkles.rectangle.stack", category: "AI", isEnabled: false, order: 42),
    ]
}

// MARK: - Notifications

extension Notification.Name {
    static let toolbarToolActivated = Notification.Name("com.swiftcode.toolbarToolActivated")
    static let showProjectTemplatesOnOpen = Notification.Name("com.swiftcode.showProjectTemplatesOnOpen")
}

// MARK: - Native macOS Toolbar Customization Delegate

public struct WorkspaceHubTool: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let iconName: String
    public let colorHex: String
    public let category: String
    public let destination: String

    public init(id: String, name: String, description: String, iconName: String, colorHex: String, category: String, destination: String) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.colorHex = colorHex
        self.category = category
        self.destination = destination
    }
}

@MainActor
public final class SwiftCodeToolbarDelegate: NSObject, NSToolbarDelegate {
    public static let shared = SwiftCodeToolbarDelegate()

    public static let itemPrefix = "com.swiftcode.toolbar."

    // All available tools from MainToolsView and comprehensive search tools
    public static let allAvailableTools: [WorkspaceHubTool] = [
        WorkspaceHubTool(id: "terminal", name: "Terminal Console", description: "Open local shells, run background commands, manage SSH nodes, and configure terminal themes.", iconName: "terminal.fill", colorHex: "#5AC8FA", category: "Utilities", destination: "terminal"),
        WorkspaceHubTool(id: "build_settings", name: "Xcode Build Settings", description: "Manage optimization levels, target SDKs, and build parameters.", iconName: "gearshape.2.fill", colorHex: "#34C759", category: "Build & Deploy", destination: "xcodeBuildSettings"),
        WorkspaceHubTool(id: "build_logs", name: "Xcode Build Logs", description: "Stream compile warnings, errors, and live build output.", iconName: "doc.text.fill", colorHex: "#FF9500", category: "Build & Deploy", destination: "xcodeBuildLogs"),
        WorkspaceHubTool(id: "ipa_builder", name: "IPA Packaging Suite", description: "Pack built iOS apps into IPA containers from SwiftCode without Xcode UI.", iconName: "shippingbox.fill", colorHex: "#AF52DE", category: "Build & Deploy", destination: "ipaBuild"),
        WorkspaceHubTool(id: "deployments", name: "Deployments Console", description: "Trigger production deployments to Netlify, Vercel, and GitHub Pages.", iconName: "cloud.fill", colorHex: "#5AC8FA", category: "Build & Deploy", destination: "deployments"),
        WorkspaceHubTool(id: "dependency_manager", name: "Dependency Manager", description: "Search, import, and manage local or remote Swift packages.", iconName: "puzzlepiece.extension.fill", colorHex: "#007AFF", category: "Utilities", destination: "dependencyManager"),
        WorkspaceHubTool(id: "source_control", name: "Source Control", description: "Inspect Git history, commits, stashes, merges, and conflicts.", iconName: "square.stack.3d.down.right.fill", colorHex: "#4CD964", category: "Git & CI", destination: "sourceControl"),
        WorkspaceHubTool(id: "ci_build", name: "CI Visual Workflows", description: "Create and monitor GitHub Actions workflow runners visually.", iconName: "play.circle.fill", colorHex: "#5856D6", category: "Git & CI", destination: "ciBuild"),
        WorkspaceHubTool(id: "simulator_main", name: "Simulator & Previews", description: "Simulate devices, manage simulators, and inspect preview screens.", iconName: "iphone", colorHex: "#FF2D55", category: "Utilities", destination: "simulatorMain"),
        WorkspaceHubTool(id: "personal_documentation", name: "Personal Documentation", description: "Access personal markdown wikis, notes, and local code references.", iconName: "book.fill", colorHex: "#A2845E", category: "Utilities", destination: "personalDocumentation"),
        WorkspaceHubTool(id: "visual_ui_builder", name: "Visual UI Builder", description: "Build modern Apple user interfaces visually for SwiftUI, AppKit, UIKit, visionOS, WidgetKit, and watchOS.", iconName: "paintpalette.fill", colorHex: "#FF2D55", category: "Utilities", destination: "visualUIBuilder"),
        WorkspaceHubTool(id: "dev_tools", name: "Developer Utility Bundle", description: "JSON formatters, base64 encoders, regex checkers, and JWT tools.", iconName: "wrench.and.screwdriver.fill", colorHex: "#FF3B30", category: "Utilities", destination: "devTools"),
        WorkspaceHubTool(id: "collaboration", name: "Live Collaboration", description: "Coordinate real-time coding sessions with team members.", iconName: "person.2.fill", colorHex: "#34C759", category: "Utilities", destination: "collaboration"),
        WorkspaceHubTool(id: "sf_symbols", name: "SF Symbols Browser", description: "Search and copy native SF Symbol identifiers.", iconName: "sparkles", colorHex: "#FFCC00", category: "Utilities", destination: "sfSymbolsBrowser"),
        WorkspaceHubTool(id: "extension_marketplace", name: "Extension Marketplace", description: "Browse and install community tools, themes, and extensions.", iconName: "bag.fill", colorHex: "#AF52DE", category: "Utilities", destination: "extensionMarketplace"),
        WorkspaceHubTool(id: "crash_log_analyzer", name: "Crash Log Analyzer", description: "Analyze production crash logs and trace symbolic memory leaks.", iconName: "doc.richtext.fill", colorHex: "#FF3B30", category: "Utilities", destination: "crashLogAnalyzer"),
        WorkspaceHubTool(id: "project_dependency_graph", name: "Project Dependency Graph", description: "Render internal project file import mapping and graphs.", iconName: "network", colorHex: "#007AFF", category: "Utilities", destination: "projectDependencyGraph"),
        WorkspaceHubTool(id: "workspace_profiles", name: "Workspace Profiles", description: "Create, edit, duplicate, and switch between workspace setting profiles.", iconName: "person.crop.square.fill.and.at.rectangle.fill", colorHex: "#34C759", category: "Utilities", destination: "workspaceProfiles"),
        WorkspaceHubTool(id: "snippets_library", name: "Snippets Library", description: "Store, tag, categorize, and quickly insert code snippet templates.", iconName: "curlybraces", colorHex: "#FF9500", category: "Utilities", destination: "snippetsLibrary"),
        WorkspaceHubTool(id: "documentation_browser", name: "Documentation Browser", description: "Full featured windowed multi-pane documentation browser and visual reference workspace.", iconName: "doc.text.magnifyingglass", colorHex: "#007AFF", category: "Utilities", destination: "documentationBrowser"),
        WorkspaceHubTool(id: "search_documentation", name: "Search Documentation", description: "Search project documentation, DocSymbols, project notes, API documentation, and other indexed resources.", iconName: "magnifyingglass", colorHex: "#AF52DE", category: "Utilities", destination: "searchDocumentation"),
        WorkspaceHubTool(id: "database_explorer", name: "Database Explorer", description: "Visually design, manage, connect, inspect, query, generate, and synchronize databases.", iconName: "cylinder.split.1x2.fill", colorHex: "#34C759", category: "Utilities", destination: "databaseExplorer"),
        WorkspaceHubTool(id: "project_inspector", name: "Project Inspector", description: "Recursive directory scanner, live modules analysis, and AI layer refactoring reviews.", iconName: "square.text.square", colorHex: "#FF9500", category: "Utilities", destination: "projectInspector"),
        WorkspaceHubTool(id: "localization_manager", name: "Localization Manager", description: "Multi-pane string catalogs and .xcstrings editor with layout previews & validation checks.", iconName: "text.book.closed.fill", colorHex: "#007AFF", category: "Utilities", destination: "localizationManager"),
        WorkspaceHubTool(id: "licenses_add", name: "Licenses", description: "Quickly add open source license templates directly to your project codebase.", iconName: "doc.text.fill", colorHex: "#FF9500", category: "Utilities", destination: "licensesAdd"),
        WorkspaceHubTool(id: "coding_dictionary", name: "Coding Dictionary", description: "AI-powered coding dictionary & reference companion that searches terminology, concepts, APIs, syntax, and patterns.", iconName: "book.pages.fill", colorHex: "#AF52DE", category: "Utilities", destination: "codingDictionary"),
        WorkspaceHubTool(id: "device_connect", name: "Device Connect", description: "Native Apple device deployment, runtime, monitoring, diagnostics, and device management platform.", iconName: "play.circle.fill", colorHex: "#34C759", category: "Build & Deploy", destination: "deviceConnect"),
        WorkspaceHubTool(id: "virtualization", name: "Virtualization", description: "Create development environments, run Linux machines, restore snapshots, and manage isolated workspaces with real telemetry.", iconName: "cpu.fill", colorHex: "#007AFF", category: "Utilities", destination: "virtualization"),
        WorkspaceHubTool(id: "code_search", name: "Code Search", description: "Search and replace code, keys, and values across entire project codebase.", iconName: "magnifyingglass", colorHex: "#007AFF", category: "Search & Navigation", destination: "codeSearch"),
        WorkspaceHubTool(id: "symbol_navigator", name: "Symbol Navigator", description: "Navigate and filter symbols, functions, and structs in active file.", iconName: "list.bullet.indent", colorHex: "#AF52DE", category: "Search & Navigation", destination: "symbolNavigator"),
        WorkspaceHubTool(id: "go_to_line", name: "Go to Line", description: "Jump directly to specific line number in current code file.", iconName: "arrow.right.to.line", colorHex: "#34C759", category: "Search & Navigation", destination: "goToLine"),
        WorkspaceHubTool(id: "file_navigator", name: "File Navigator", description: "Toggle workspace file tree navigator panel.", iconName: "sidebar.left", colorHex: "#007AFF", category: "Search & Navigation", destination: "fileNavigator")
    ]

    public static func identifier(for tool: WorkspaceHubTool) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("\(itemPrefix)\(tool.id)")
    }

    public static func tool(for identifier: NSToolbarItem.Identifier) -> WorkspaceHubTool? {
        let raw = identifier.rawValue
        if raw.hasPrefix(itemPrefix) {
            let toolId = String(raw.dropFirst(itemPrefix.count))
            return allAvailableTools.first(where: { $0.id == toolId || $0.destination == toolId })
        }
        return allAvailableTools.first(where: { $0.id == raw || $0.destination == raw })
    }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tool = Self.tool(for: itemIdentifier) else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tool.name
        item.paletteLabel = tool.name
        item.toolTip = tool.description
        if let img = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.name) {
            item.image = img
        } else {
            item.image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: tool.name)
        }
        item.target = self
        item.action = #selector(handleToolbarAction(_:))
        return item
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var defaults: [NSToolbarItem.Identifier] = []
        if let codeSearch = Self.allAvailableTools.first(where: { $0.id == "code_search" }) {
            defaults.append(Self.identifier(for: codeSearch))
        }
        if let searchDocs = Self.allAvailableTools.first(where: { $0.id == "search_documentation" }) {
            defaults.append(Self.identifier(for: searchDocs))
        }
        if let symbolNav = Self.allAvailableTools.first(where: { $0.id == "symbol_navigator" }) {
            defaults.append(Self.identifier(for: symbolNav))
        }
        if let terminal = Self.allAvailableTools.first(where: { $0.id == "terminal" }) {
            defaults.append(Self.identifier(for: terminal))
        }
        defaults.append(.flexibleSpace)
        return defaults
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var allowed: [NSToolbarItem.Identifier] = Self.allAvailableTools.map { Self.identifier(for: $0) }
        allowed.append(contentsOf: [.space, .flexibleSpace])
        return allowed
    }

    @objc private func handleToolbarAction(_ sender: NSToolbarItem) {
        if let tool = Self.tool(for: sender.itemIdentifier) {
            let targetID = tool.destination.isEmpty ? tool.id : tool.destination
            NotificationCenter.default.post(
                name: .toolbarToolActivated,
                object: nil,
                userInfo: ["toolID": targetID]
            )
        }
    }

    public static func presentCustomizationPalette() {
        let window = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApplication.shared.windows.first(where: { $0.isVisible && $0.toolbar != nil && !($0 is NSPanel) })

        if let toolbar = window?.toolbar {
            toolbar.runCustomizationPalette(nil)
        } else {
            NotificationCenter.default.post(
                name: .toolbarToolActivated,
                object: nil,
                userInfo: ["toolID": "toolbarCustomization"]
            )
        }
    }
}
