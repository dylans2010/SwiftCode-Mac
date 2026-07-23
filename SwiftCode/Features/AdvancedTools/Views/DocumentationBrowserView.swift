import SwiftUI
import AppKit
import WebKit

// MARK: - Native Window Manager
@MainActor
public final class DocumentationBrowserWindowManager: NSObject, NSWindowDelegate {
    public static let shared = DocumentationBrowserWindowManager()
    private var windowController: DocumentationBrowserWindowController?

    public func showWindow() {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let wc = DocumentationBrowserWindowController()
        wc.window?.delegate = self
        self.windowController = wc
        wc.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        windowController?.close()
        windowController = nil
    }

    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}

// MARK: - Native Window Controller
@MainActor
public class DocumentationBrowserWindowController: NSWindowController {
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Documentation Browser Workspace"
        window.minSize = NSSize(width: 1200, height: 800)
        window.setFrameAutosaveName("DocumentationBrowserMainWindow")
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        super.init(window: window)

        let hostingVC = NSHostingController(rootView: NativeDocumentationBrowserWorkspaceView())
        hostingVC.sizingOptions = []
        window.contentViewController = hostingVC

        setupToolbar(window: window)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar(window: NSWindow) {
        let toolbar = NSToolbar(identifier: "DocumentationBrowserToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }
}

// ====================================================================
// NATIVE DOCUMENTATION BROWSER - MAIN ENTRY POINT sheet view fallback
// ====================================================================

public struct DocumentationBrowserView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.pages.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.orange)

            Text("Apple Developer Documentation Browser")
                .font(.title2.bold())

            Text("The browser opens in a dedicated native macOS window with full multi-column split layout, search histories, bookmarks, and table of contents sidebars.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Open Documentation Window") {
                DocumentationBrowserWindowManager.shared.showWindow()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 500, height: 400)
        .onAppear {
            DocumentationBrowserWindowManager.shared.showWindow()
        }
    }
}

// MARK: - Core Models for Documentation indexing

struct DocSymbol: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let kind: String // "class", "struct", "protocol", "func"
    let framework: String
    let summary: String
    let syntax: String
    let platforms: [String]
    let availability: String
}

// MARK: - Native Workspace View UI

struct NativeDocumentationBrowserWorkspaceView: View {
    // Search states (smooth asynchronous tracking)
    @State private var searchQuery = ""
    @State private var debouncedSearchQuery = ""
    @State private var selectedCategory = "All"
    @State private var selectedFramework = "All"
    @State private var selectedPlatform = "All"

    // Core selection
    @State private var selectedSymbol: DocSymbol? = nil
    @State private var favorites: Set<String> = []
    @State private var searchHistory: [String] = []
    @State private var recentlyViewed: [String] = []

    // Asynchronous loading/searching tasks
    @State private var isSearching = false
    @State private var symbols: [DocSymbol] = []

    // Layout lists
    let categories = ["All", "Classes", "Structs", "Protocols", "Functions"]
    let frameworks = ["All", "SwiftUI", "Swift", "Foundation", "AppKit", "UIKit"]
    let platforms = ["All", "macOS", "iOS", "watchOS", "tvOS"]

    // Statistics
    private var docStatistics: String {
        "Index Count: \(symbols.count) | Favorites: \(favorites.count) | History: \(searchHistory.count)"
    }

    var body: some View {
        HSplitView {
            // Sidebar Navigation: Categories & Stats
            VStack(alignment: .leading, spacing: 0) {
                List {
                    Section("Overview") {
                        Button(action: { selectedCategory = "All" }) {
                            Label("All Documentation", systemImage: "book.fill")
                        }
                        .buttonStyle(.plain)

                        Button(action: { selectedCategory = "Favorites" }) {
                            Label("Bookmarks & Favorites", systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                        .buttonStyle(.plain)

                        Button(action: { selectedCategory = "Recent" }) {
                            Label("Recently Viewed", systemImage: "clock.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    Section("Framework Browser") {
                        ForEach(frameworks.filter { $0 != "All" }, id: \.self) { fw in
                            Button(action: { selectedFramework = fw; selectedCategory = "All" }) {
                                Label(fw, systemImage: "square.stack.3d.down.right")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section("Platform Availability") {
                        ForEach(platforms.filter { $0 != "All" }, id: \.self) { plt in
                            Button(action: { selectedPlatform = plt; selectedCategory = "All" }) {
                                Label(plt, systemImage: "laptopcomputer")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Statistics Bottom Bar
                VStack(alignment: .leading, spacing: 4) {
                    Text("DOCUMENTATION STATISTICS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(docStatistics)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)

            // Center List of symbols/topics (Smooth responsive search list)
            VStack(spacing: 0) {
                // Smooth search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search symbols, APIs, packages...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .onChange(of: searchQuery) { _, newValue in
                            triggerAsynchronousSearch(newValue)
                        }
                    if isSearching {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))

                Divider()

                // Symbol Results List
                if filteredSymbols.isEmpty {
                    ContentUnavailableView("No Symbols Found", systemImage: "doc.text.magnifyingglass")
                        .frame(maxHeight: .infinity)
                } else {
                    List(filteredSymbols, selection: $selectedSymbol) { sym in
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(kindColor(sym.kind).opacity(0.12))
                                    .frame(width: 18, height: 18)
                                Text(sym.kind.prefix(1).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(kindColor(sym.kind))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(sym.name).bold()
                                Text("\(sym.framework) | \(sym.availability)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .tag(sym)
                    }
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

            // Right Pane: Rich Symbol Details / Workspace
            Group {
                if let sym = selectedSymbol {
                    symbolDetailsPane(sym)
                } else {
                    ContentUnavailableView(
                        "Documentation Home",
                        systemImage: "book.pages",
                        description: Text("Search or filter Apple documentation. Select a class, struct, or protocol to inspect its inheritance relationships, code snippets, syntax parameters, and platforms.")
                    )
                }
            }
            .frame(minWidth: 450)
        }
        .onAppear {
            loadMockDocumentationIndex()
        }
    }

    // MARK: - Details Panel

    private func symbolDetailsPane(_ sym: DocSymbol) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Breadcrumbs & Link Action
                HStack {
                    Text("Developer Documentation > \(sym.framework) > \(sym.kind.uppercased())")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()

                    Button {
                        toggleFavorite(sym.name)
                    } label: {
                        Image(systemName: favorites.contains(sym.name) ? "star.fill" : "star")
                            .foregroundStyle(favorites.contains(sym.name) ? .yellow : .primary)
                    }
                    .buttonStyle(.plain)
                }

                // Title
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text(sym.name)
                            .font(.title.bold())

                        Text(sym.kind.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(kindColor(sym.kind).opacity(0.12))
                            .foregroundStyle(kindColor(sym.kind))
                            .cornerRadius(4)
                    }

                    Text("Framework: \(sym.framework) | Availability: \(sym.availability)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Overview Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.headline)
                    Text(sym.summary)
                        .font(.body)
                        .lineSpacing(4)
                }

                // Syntax & Copy Code Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Declaration Syntax")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy Code") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(sym.syntax, forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text(sym.syntax)
                            .font(.system(.body, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.12))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                    .padding(6)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Relationships Map
                VStack(alignment: .leading, spacing: 10) {
                    Text("Symbol Relationships")
                        .font(.headline)

                    GroupBox {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Inherits From")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("NSObject")
                                    .font(.subheadline.bold())
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Conforms To")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Sendable, Identifiable, Decodable")
                                    .font(.subheadline.bold())
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Platforms
                VStack(alignment: .leading, spacing: 8) {
                    Text("Platform Support")
                        .font(.headline)
                    HStack(spacing: 8) {
                        ForEach(sym.platforms, id: \.self) { plt in
                            Text(plt)
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }

                // External documentation link
                Link(destination: URL(string: "https://developer.apple.com/documentation/\(sym.framework.lowercased())/\(sym.name.lowercased())")!) {
                    Label("Open in Apple Reference Website", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: sym) { _, newValue in
            addToRecents(newValue.name)
        }
    }

    // MARK: - Search Filtering Logic

    private var filteredSymbols: [DocSymbol] {
        var list = symbols

        // Overview Selection Filters
        if selectedCategory == "Favorites" {
            list = list.filter { favorites.contains($0.name) }
        } else if selectedCategory == "Recent" {
            list = list.filter { recentlyViewed.contains($0.name) }
        } else if selectedCategory != "All" {
            let kindMap = ["Classes": "class", "Structs": "struct", "Protocols": "protocol", "Functions": "func"]
            if let targetKind = kindMap[selectedCategory] {
                list = list.filter { $0.kind == targetKind }
            }
        }

        // Search Query Filter (Uses debounced/smooth text to prevent UI freeze)
        if !debouncedSearchQuery.isEmpty {
            let q = debouncedSearchQuery.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.summary.lowercased().contains(q)
            }
        }

        // Framework Filter
        if selectedFramework != "All" {
            list = list.filter { $0.framework == selectedFramework }
        }

        // Platform Filter
        if selectedPlatform != "All" {
            list = list.filter { $0.platforms.contains(selectedPlatform) }
        }

        return list
    }

    // MARK: - Actions Operations

    private func triggerAsynchronousSearch(_ query: String) {
        isSearching = true

        // Debounce search safely to guarantee responsive UI typing
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms delay
            await MainActor.run {
                self.debouncedSearchQuery = query
                self.isSearching = false
                if !query.isEmpty && !searchHistory.contains(query) {
                    searchHistory.append(query)
                }
            }
        }
    }

    private func toggleFavorite(_ name: String) {
        if favorites.contains(name) {
            favorites.remove(name)
        } else {
            favorites.insert(name)
        }
    }

    private func addToRecents(_ name: String) {
        recentlyViewed.removeAll { $0 == name }
        recentlyViewed.insert(name, at: 0)
        recentlyViewed = Array(recentlyViewed.prefix(12))
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "class": return .purple
        case "struct": return .blue
        case "protocol": return .orange
        default: return .green
        }
    }

    private func loadMockDocumentationIndex() {
        symbols = [
            DocSymbol(name: "VStack", kind: "struct", framework: "SwiftUI", summary: "A view that arranges its subviews in a vertical line.", syntax: "struct VStack<Content> : View where Content : View", platforms: ["macOS", "iOS", "watchOS", "tvOS"], availability: "iOS 13.0+"),
            DocSymbol(name: "HStack", kind: "struct", framework: "SwiftUI", summary: "A view that arranges its subviews in a horizontal line.", syntax: "struct HStack<Content> : View where Content : View", platforms: ["macOS", "iOS", "watchOS", "tvOS"], availability: "iOS 13.0+"),
            DocSymbol(name: "List", kind: "struct", framework: "SwiftUI", summary: "A container that presents rows of data arranged in a single column.", syntax: "struct List<SelectionValue, Content> : View where SelectionValue : Hashable, Content : View", platforms: ["macOS", "iOS", "tvOS"], availability: "iOS 13.0+"),
            DocSymbol(name: "URLSession", kind: "class", framework: "Foundation", summary: "An object that coordinates a group of related, network data-transfer tasks.", syntax: "class URLSession : NSObject, Sendable", platforms: ["macOS", "iOS", "watchOS", "tvOS"], availability: "iOS 7.0+"),
            DocSymbol(name: "JSONDecoder", kind: "class", framework: "Foundation", summary: "An object that decodes instances of a data type from JSON objects.", syntax: "class JSONDecoder", platforms: ["macOS", "iOS", "watchOS", "tvOS"], availability: "iOS 10.0+"),
            DocSymbol(name: "NSWindow", kind: "class", framework: "AppKit", summary: "A window that an app displays on the screen.", syntax: "class NSWindow : NSResponder", platforms: ["macOS"], availability: "macOS 10.0+"),
            DocSymbol(name: "Task", kind: "struct", framework: "Swift", summary: "A unit of asynchronous work.", syntax: "struct Task<Success, Failure> : Sendable where Success : Sendable, Failure : Error", platforms: ["macOS", "iOS", "watchOS", "tvOS"], availability: "iOS 15.0+"),
            DocSymbol(name: "Actor", kind: "protocol", framework: "Swift", summary: "A common protocol that all actors conform to.", syntax: "protocol Actor : AnyObject, Sendable", platforms: ["macOS", "iOS", "watchOS", "tvOS"], availability: "iOS 15.0+")
        ]
    }
}
