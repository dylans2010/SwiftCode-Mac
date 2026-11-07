import SwiftUI
import AppKit

public enum SCToolCategory: String, CaseIterable, Identifiable, Sendable {
    case visual = "Visual & Interface"
    case development = "Core Development"
    case deployment = "Packaging & Devices"
    case data = "Data & Reference"

    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .visual: return "paintpalette"
        case .development: return "hammer"
        case .deployment: return "shippingbox"
        case .data: return "cylinder.split.1x2"
        }
    }
}

public struct SCToolItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let icon: String
    public let category: SCToolCategory
    public let actionIdentifier: String

    public init(id: String, name: String, description: String, icon: String, category: SCToolCategory, actionIdentifier: String) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.category = category
        self.actionIdentifier = actionIdentifier
    }
}

@MainActor
public final class SCToolsRegistry: ObservableObject {
    public static let shared = SCToolsRegistry()

    @Published public var tools: [SCToolItem] = [
        SCToolItem(id: "symbols", name: "SF Symbols Browser", description: "Browse, inspect, and copy system icon definitions and rendering styles.", icon: "sparkles", category: .visual, actionIdentifier: "openSymbols"),
        SCToolItem(id: "artboards", name: "Visual UI Builder & Artboards", description: "Design multi-screen visual artboard layouts and preview live interfaces.", icon: "square.grid.2x2", category: .visual, actionIdentifier: "openArtboards"),
        SCToolItem(id: "database", name: "Database Management", description: "SQLite, Core Data, and relational schema inspection, migrations, and queries.", icon: "cylinder.split.1x2", category: .data, actionIdentifier: "openDatabase"),
        SCToolItem(id: "virtualization", name: "Virtualization Console", description: "Virtual machine hypervisor, guest configurations, and disk image inspection.", icon: "server.rack", category: .development, actionIdentifier: "openVirtualization"),
        SCToolItem(id: "deviceConnect", name: "Device Connect", description: "Pair, inspect, and debug physical iPhones, iPads, and tethered development hardware.", icon: "cable.connector", category: .deployment, actionIdentifier: "openDeviceConnect"),
        SCToolItem(id: "ipaPackaging", name: "IPA Packaging & Signing", description: "Build, package, sign, and export standalone iOS and macOS application archives.", icon: "shippingbox.fill", category: .deployment, actionIdentifier: "openIPAPackaging"),
        SCToolItem(id: "codingDictionary", name: "Coding Dictionary", description: "Comprehensive Apple SDK API documentation and development terminology dictionary.", icon: "character.book.closed", category: .data, actionIdentifier: "openDictionary"),
        SCToolItem(id: "ciWorkflows", name: "CI Visual Workflows", description: "Build, configure, and monitor automated continuous integration workflows.", icon: "arrow.triangle.pull", category: .development, actionIdentifier: "openCIWorkflows"),
        SCToolItem(id: "terminal", name: "Integrated Terminal", description: "Sandboxed command-line shell with integrated process execution.", icon: "terminal", category: .development, actionIdentifier: "openTerminal")
    ]

    private init() {}
}

public struct SCToolsView: View {
    @ObservedObject private var registry = SCToolsRegistry.shared
    @State private var selectedCategory: SCToolCategory? = nil
    @State private var searchQuery: String = ""
    @State private var activeSheetItem: SCToolItem? = nil
    @Environment(\.dismiss) private var dismiss

    public var workspaceFolder: URL?
    public var onLaunchTool: ((SCToolItem) -> Void)? = nil

    public init(workspaceFolder: URL? = nil, onLaunchTool: ((SCToolItem) -> Void)? = nil) {
        self.workspaceFolder = workspaceFolder
        self.onLaunchTool = onLaunchTool
    }

    private var effectiveFolder: URL {
        workspaceFolder ?? FileManager.default.temporaryDirectory
    }

    private var filteredTools: [SCToolItem] {
        registry.tools.filter { tool in
            let matchesCategory = selectedCategory == nil || tool.category == selectedCategory
            let matchesSearch = searchQuery.isEmpty || tool.name.localizedCaseInsensitiveContains(searchQuery) || tool.description.localizedCaseInsensitiveContains(searchQuery)
            return matchesCategory && matchesSearch
        }
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedCategory) {
                NavigationLink(value: Optional<SCToolCategory>.none) {
                    Label("All Tools", systemImage: "square.grid.2x2.fill")
                }
                Section("Categories") {
                    ForEach(SCToolCategory.allCases) { category in
                        NavigationLink(value: Optional(category)) {
                            Label(category.rawValue, systemImage: category.icon)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Tools Drawer")
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 16)], spacing: 16) {
                        ForEach(filteredTools) { tool in
                            toolCard(tool)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(selectedCategory?.rawValue ?? "All Development Tools")
            .searchable(text: $searchQuery, prompt: "Search development tools...")
        }
        .frame(minWidth: 780, minHeight: 520)
        .sheet(item: $activeSheetItem) { item in
            toolDestinationView(for: item)
        }
    }

    @ViewBuilder
    private func toolCard(_ tool: SCToolItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: tool.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(tool.category.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(tool.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button {
                    launch(tool)
                } label: {
                    Text("Open Tool")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func launch(_ tool: SCToolItem) {
        if let onLaunchTool {
            onLaunchTool(tool)
            return
        }

        switch tool.actionIdentifier {
        case "openSymbols":
            SFSymbolBrowserWindowManager.shared.showWindow()
        case "openDatabase":
            DatabaseExplorerWindowManager.shared.showWindow()
        case "openVirtualization":
            VirtualizationWindowManager.shared.showWindow()
        case "openArtboards":
            ArtboardWindowManager.shared.showWindow(workspaceFolder: effectiveFolder)
        case "openIPAPackaging":
            IPABuildWindowManager.shared.showWindow()
        case "openDictionary":
            CodingDictionaryWindowManager.shared.showWindow()
        case "openCIWorkflows":
            CIWindowManager.shared.showWindow(workspaceFolder: effectiveFolder)
        case "openTerminal":
            SandboxTerminalWindowManager.shared.showWindow(workspaceFolder: effectiveFolder)
        case "openDeviceConnect":
            activeSheetItem = tool
        default:
            activeSheetItem = tool
        }
    }

    @ViewBuilder
    private func toolDestinationView(for tool: SCToolItem) -> some View {
        NavigationStack {
            VStack {
                switch tool.actionIdentifier {
                case "openIPAPackaging":
                    IPABuildView()
                case "openSymbols":
                    SFSymbolBrowserView()
                default:
                    VStack(spacing: 16) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                        Text(tool.name).font(.title2.bold())
                        Text(tool.description).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { activeSheetItem = nil }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

@MainActor
public final class SCToolsWindowManager: NSObject {
    public static let shared = SCToolsWindowManager()
    private var controller: SCToolsWindowController?

    public func showWindow(workspaceFolder: URL? = nil) {
        if let existing = controller {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = SCToolsWindowController(workspaceFolder: workspaceFolder)
        self.controller = controller
        controller.window?.delegate = self
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func toggle(workspaceFolder: URL? = nil) {
        if let controller, controller.window?.isVisible == true {
            controller.close()
        } else {
            showWindow(workspaceFolder: workspaceFolder)
        }
    }
}

extension SCToolsWindowManager: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === controller?.window {
            controller = nil
        }
    }
}

@MainActor
public final class SCToolsWindowController: NSWindowController {
    public let workspaceFolder: URL?

    public init(workspaceFolder: URL? = nil) {
        self.workspaceFolder = workspaceFolder
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SwiftCode Centralized Tools Drawer"
        window.center()
        window.setFrameAutosaveName("SwiftCodeSCToolsWindow")
        let rootView = SCToolsView(workspaceFolder: workspaceFolder)
        window.contentView = NSHostingView(rootView: rootView)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
