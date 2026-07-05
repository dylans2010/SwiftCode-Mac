import Foundation

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
        ToolbarTool(id: "code_search", name: "Code Search", icon: "magnifyingglass", category: "Navigation", isEnabled: true, order: 0),
        ToolbarTool(id: "errors_viewer", name: "Errors Viewer", icon: "exclamationmark.triangle.fill", category: "Diagnostics", isEnabled: true, order: 1),
        ToolbarTool(id: "dependency_manager", name: "Dependencies", icon: "shippingbox.fill", category: "Project", isEnabled: true, order: 2),
        ToolbarTool(id: "file_navigator", name: "File Navigator", icon: "folder.fill", category: "Navigation", isEnabled: true, order: 3),
        ToolbarTool(id: "build_trigger", name: "Build", icon: "hammer.fill", category: "Build", isEnabled: true, order: 4),
        ToolbarTool(id: "command_palette", name: "Command Palette", icon: "terminal.fill", category: "Tools", isEnabled: true, order: 5),
        ToolbarTool(id: "go_to_line", name: "Go to Line", icon: "arrow.right.to.line", category: "Navigation", isEnabled: true, order: 6),
        ToolbarTool(id: "symbol_navigator", name: "Symbol Navigator", icon: "list.bullet.indent", category: "Navigation", isEnabled: true, order: 7),
        ToolbarTool(id: "github_actions", name: "GitHub Actions", icon: "arrow.triangle.2.circlepath.circle.fill", category: "Git", isEnabled: true, order: 8),
        ToolbarTool(id: "local_simulation", name: "Preview", icon: "play.display", category: "Build", isEnabled: true, order: 9),
        ToolbarTool(id: "collaboration", name: "Collaboration", icon: "person.2.badge.gearshape.fill", category: "Project", isEnabled: true, order: 10),

        ToolbarTool(id: "project_settings", name: "Project Settings", icon: "gearshape.fill", category: "Project", isEnabled: false, order: 10),
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
        ToolbarTool(id: "deployments", name: "Deployments", icon: "cloud.fill", category: "Tools", isEnabled: true, order: 39),
        ToolbarTool(id: "run_tests", name: "Run Tests", icon: "play.shield.fill", category: "Diagnostics", isEnabled: true, order: 40),
        ToolbarTool(id: "gist_manager", name: "Gist Manager", icon: "tray.full.fill", category: "Git", isEnabled: true, order: 41),
        ToolbarTool(id: "assist_view", name: "Assist", icon: "sparkles.rectangle.stack", category: "AI", isEnabled: false, order: 42),
    ]
}

// MARK: - Notifications

extension Notification.Name {
    static let toolbarToolActivated = Notification.Name("com.swiftcode.toolbarToolActivated")
    static let showProjectTemplatesOnOpen = Notification.Name("com.swiftcode.showProjectTemplatesOnOpen")
}
