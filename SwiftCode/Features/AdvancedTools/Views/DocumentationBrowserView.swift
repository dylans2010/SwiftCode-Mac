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
            contentRect: NSRect(x: 100, y: 100, width: 1400, height: 900),
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
// NATIVE DOCUMENTATION BROWSER - MAIN ENTRY POINT
// ====================================================================

public struct DocumentationBrowserView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                DocumentationBrowserWindowManager.shared.showWindow()
                dismiss()
            }
    }
}

// MARK: - Core Models for Documentation Indexing

struct DocSymbol: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let kind: String // "class", "struct", "protocol", "func"
    let framework: String
    let summary: String
    let syntax: String
    let platforms: [String: String] // Platform -> Introduced version (e.g., "macOS": "10.15")
    let inheritsFrom: String?
    let conformsTo: [String]
    let codeSample: String
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
    @State private var favorites: Set<String> = ["VStack", "URLSession"]
    @State private var searchHistory: [String] = ["VStack", "Task", "JSONDecoder"]
    @State private var recentlyViewed: [String] = ["VStack", "JSONDecoder"]

    // Asynchronous loading/searching tasks
    @State private var isSearching = false
    @State private var symbols: [DocSymbol] = []

    // Layout lists
    let categories = ["All", "Classes", "Structs", "Protocols", "Functions"]
    let frameworks = ["All", "SwiftUI", "Swift", "Foundation", "AppKit", "UIKit"]
    let platforms = ["All", "macOS", "iOS", "watchOS", "tvOS"]

    // Statistics
    private var docStatistics: String {
        "Index Count: \(symbols.count) | Bookmarks: \(favorites.count) | History: \(searchHistory.count)"
    }

    var body: some View {
        HSplitView {
            // Sidebar Navigation: Categories & Stats with refined visual theme
            VStack(alignment: .leading, spacing: 0) {
                // Top header
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text("Developer Bookshelf")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                List {
                    Section {
                        Button(action: { selectedCategory = "All"; selectedFramework = "All"; selectedPlatform = "All" }) {
                            HStack {
                                Label("All Documentation", systemImage: "book.pages.fill")
                                    .foregroundStyle(.orange)
                                Spacer()
                                Text("\(symbols.count)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)

                        Button(action: { selectedCategory = "Favorites" }) {
                            HStack {
                                Label("Bookmarks & Favorites", systemImage: "star.fill")
                                    .foregroundStyle(.yellow)
                                Spacer()
                                Text("\(favorites.count)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)

                        Button(action: { selectedCategory = "Recent" }) {
                            HStack {
                                Label("Recently Viewed", systemImage: "clock.fill")
                                    .foregroundStyle(.blue)
                                Spacer()
                                Text("\(recentlyViewed.count)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    } header: {
                        Text("Overview").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    }

                    Section {
                        ForEach(frameworks.filter { $0 != "All" }, id: \.self) { fw in
                            Button(action: { selectedFramework = fw; selectedCategory = "All" }) {
                                HStack {
                                    Label(fw, systemImage: "square.stack.3d.down.right.fill")
                                        .foregroundStyle(.purple)
                                    Spacer()
                                    let count = symbols.filter { $0.framework == fw }.count
                                    Text("\(count)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Framework Browser").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    }

                    Section {
                        ForEach(platforms.filter { $0 != "All" }, id: \.self) { plt in
                            Button(action: { selectedPlatform = plt; selectedCategory = "All" }) {
                                Label(plt, systemImage: "laptopcomputer")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Platform Availability").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Statistics Bottom Bar
                VStack(alignment: .leading, spacing: 6) {
                    Text("DOCUMENTATION METRICS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(docStatistics)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(minWidth: 240, idealWidth: 260, maxWidth: 320)

            // Center List of symbols/topics (Premium visual search list)
            VStack(spacing: 0) {
                // Modern search bar with larger padding and rounded style
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Search symbols, APIs, packages...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .onChange(of: searchQuery) { _, newValue in
                            triggerAsynchronousSearch(newValue)
                        }
                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .padding(12)

                Divider()

                // Filter Header Summary
                HStack {
                    Text("Showing \(filteredSymbols.count) matches")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if selectedFramework != "All" || selectedPlatform != "All" || selectedCategory != "All" {
                        Button("Reset Filters") {
                            selectedFramework = "All"
                            selectedPlatform = "All"
                            selectedCategory = "All"
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.04))

                Divider()

                // Symbol Results List
                if filteredSymbols.isEmpty {
                    ContentUnavailableView("No Symbols Found", systemImage: "doc.text.magnifyingglass")
                        .frame(maxHeight: .infinity)
                } else {
                    List(filteredSymbols, selection: $selectedSymbol) { sym in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(kindColor(sym.kind).opacity(0.15))
                                    .frame(width: 28, height: 28)
                                Text(sym.kind.prefix(1).uppercased())
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(kindColor(sym.kind))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(sym.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("\(sym.framework) | \(sym.availability)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .tag(sym)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)

            // Right Pane: High-Fidelity Rich Symbol Details or Custom Interactive Dashboard
            Group {
                if let sym = selectedSymbol {
                    symbolDetailsPane(sym)
                } else {
                    documentationHubHomeView()
                }
            }
            .frame(minWidth: 600)
        }
        .onAppear {
            loadMockDocumentationIndex()
        }
    }

    // MARK: - Premium Platform / Framework Reference Hub Homepage

    private func documentationHubHomeView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Main visual greeting banner
                VStack(alignment: .leading, spacing: 8) {
                    Text("SwiftCode Developer Portal")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)

                    Text("Apple SDK & Language Reference")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(.primary)

                    Text("Search components, investigate inheritance graphs, inspect availability, and copy production-ready code declarations.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)

                // Grid of Frameworks
                VStack(alignment: .leading, spacing: 14) {
                    Text("CHOOSE A FRAMEWORK")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20)], spacing: 20) {
                        frameworkHubCard(name: "SwiftUI", icon: "square.stack.3d.down.right.fill", color: .purple, description: "Declarative layouts across all Apple platforms with state management and dynamic updates.")
                        frameworkHubCard(name: "Swift Language", icon: "swift", color: .orange, description: "Strong types, safety, fast performance, modern concurrency actors, and advanced generic constraints.")
                        frameworkHubCard(name: "Foundation", icon: "square.grid.3x3.topleft.filled", color: .blue, description: "Essential resource mapping, dates, numbers, URLSession requests, JSON formatting, and locale parsing.")
                        frameworkHubCard(name: "AppKit & UIKit", icon: "macbook.and.iphone", color: .green, description: "Traditional AppKit windows, responder chains, split controllers, and platform-specific view delegates.")
                    }
                }

                // Interactive Pro-Tips/Guides Card
                VStack(alignment: .leading, spacing: 14) {
                    Text("POPULAR TOPICS & RECIPES")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Developer Pro-Tips", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(.yellow)
                                Spacer()
                            }

                            Divider()

                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("💡 Modern Swift Concurrency")
                                        .font(.subheadline.bold())
                                    Text("Prefer async/await Task structures and isolation-level Actors to completely eliminate runtime multi-threaded race conditions in Apple UI frameworks.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Divider()

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("💡 High Performance Lists")
                                        .font(.subheadline.bold())
                                    Text("Utilize LazyVStack or List structures in SwiftUI to optimize cell recycling. Bind simple ID structures to guarantee smooth scroll performance on older screens.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Statistics Metrics Summary
                HStack(spacing: 24) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("Fully Synchronized")
                                .font(.subheadline.bold())
                            Text("Apple Developer Index SDK 17.4")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().frame(height: 35)

                    HStack(spacing: 10) {
                        Image(systemName: "bookmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text("\(favorites.count) Bookmarks Saved")
                                .font(.subheadline.bold())
                            Text("Quick-reference shortcuts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 10)
            }
            .padding(40)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func frameworkHubCard(name: String, icon: String, color: Color, description: String) -> some View {
        Button {
            selectedFramework = name == "Swift Language" ? "Swift" : name
            selectedCategory = "All"
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(color.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(color)
                    }
                    Spacer()
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.3))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                }
            }
            .padding(20)
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Premium Details Panel

    private func symbolDetailsPane(_ sym: DocSymbol) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Breadcrumbs & Link Action
                HStack {
                    Text("Developer Documentation  >  \(sym.framework)  >  \(sym.kind.uppercased())")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()

                    Button {
                        toggleFavorite(sym.name)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: favorites.contains(sym.name) ? "star.fill" : "star")
                                .foregroundStyle(favorites.contains(sym.name) ? .yellow : .secondary)
                            Text(favorites.contains(sym.name) ? "Bookmarked" : "Bookmark")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                // Title Area
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(sym.name)
                            .font(.system(size: 40, weight: .black))

                        Text(sym.kind.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(kindColor(sym.kind).opacity(0.15))
                            .foregroundStyle(kindColor(sym.kind))
                            .cornerRadius(6)
                    }

                    Text("Framework: \(sym.framework)  |  Availability: \(sym.availability)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Overview Description
                VStack(alignment: .leading, spacing: 10) {
                    Text("Overview")
                        .font(.title2.bold())
                    Text(sym.summary)
                        .font(.system(size: 15))
                        .lineSpacing(6)
                        .foregroundColor(.primary)
                }

                // Declaration Syntax & Copy Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("DECLARATION SYNTAX", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 10, weight: .bold))
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
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(8)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Dynamic Relationships Explorer Graph Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Symbol Relationships Graph")
                        .font(.title2.bold())

                    GroupBox {
                        HStack(spacing: 0) {
                            // Ancestors / Inherits
                            VStack(alignment: .center, spacing: 8) {
                                Text("INHERITS FROM")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)

                                Text(sym.inheritsFrom ?? "None (Base)")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .frame(maxWidth: .infinity)

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary.opacity(0.4))

                            // Current Class/Struct
                            VStack(alignment: .center, spacing: 8) {
                                Text("CURRENT SYMBOL")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)

                                Text(sym.name)
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(kindColor(sym.kind).opacity(0.15))
                                    .cornerRadius(6)
                            }
                            .frame(maxWidth: .infinity)

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary.opacity(0.4))

                            // Conformances
                            VStack(alignment: .center, spacing: 8) {
                                Text("CONFORMS TO")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)

                                Text(sym.conformsTo.joined(separator: ", "))
                                    .font(.system(size: 11, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 14)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Sample Playground Code block
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Usage Sample Playground")
                            .font(.title2.bold())
                        Spacer()
                        Button("Copy Example") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(sym.codeSample, forType: .string)
                        }
                        .buttonStyle(.plain)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    }

                    TextEditor(text: .constant(sym.codeSample))
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 180)
                        .padding(10)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                }

                // Modern Interactive Platforms Grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("Detailed Platform Support")
                        .font(.title2.bold())

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
                        ForEach(platforms.filter { $0 != "All" }, id: \.self) { plt in
                            let version = sym.platforms[plt] ?? "Not Supported"
                            let isSupported = version != "Not Supported"

                            VStack(spacing: 8) {
                                Text(plt)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)

                                Text(version)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(isSupported ? .green : .secondary.opacity(0.5))

                                Text(isSupported ? "Supported" : "N/A")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isSupported ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                                    .foregroundStyle(isSupported ? .green : .secondary)
                                    .cornerRadius(4)
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                            )
                        }
                    }
                }

                Divider().padding(.vertical, 10)

                // External documentation link
                Link(destination: URL(string: "https://developer.apple.com/documentation/\(sym.framework.lowercased())/\(sym.name.lowercased())")!) {
                    Label("Open Official Apple Reference Documentation", systemImage: "safari")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.orange)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(40)
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
                $0.summary.lowercased().contains(q) ||
                $0.framework.lowercased().contains(q)
            }
        }

        // Framework Filter
        if selectedFramework != "All" {
            list = list.filter { $0.framework == selectedFramework }
        }

        // Platform Filter
        if selectedPlatform != "All" {
            list = list.filter { $0.platforms[selectedPlatform] != nil }
        }

        return list
    }

    // MARK: - Actions Operations

    private func triggerAsynchronousSearch(_ query: String) {
        isSearching = true

        // Debounce search safely to guarantee responsive UI typing
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000) // 120ms delay
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
            DocSymbol(
                name: "VStack",
                kind: "struct",
                framework: "SwiftUI",
                summary: "A view that arranges its subviews in a vertical line with customizable alignments, line-spacings, and child layout priority distributions.",
                syntax: "struct VStack<Content> : View where Content : View",
                platforms: ["macOS": "10.15", "iOS": "13.0", "watchOS": "6.0", "tvOS": "13.0"],
                inheritsFrom: nil,
                conformsTo: ["View", "Sendable"],
                codeSample: "VStack(alignment: .leading, spacing: 12) {\n    Text(\"Main Title\").font(.largeTitle)\n    Text(\"Subtitle description.\").foregroundColor(.secondary)\n}",
                availability: "iOS 13.0+"
            ),
            DocSymbol(
                name: "HStack",
                kind: "struct",
                framework: "SwiftUI",
                summary: "A view that arranges its subviews in a horizontal line, aligning children based on custom layout anchors and alignment guidelines.",
                syntax: "struct HStack<Content> : View where Content : View",
                platforms: ["macOS": "10.15", "iOS": "13.0", "watchOS": "6.0", "tvOS": "13.0"],
                inheritsFrom: nil,
                conformsTo: ["View", "Sendable"],
                codeSample: "HStack(alignment: .center, spacing: 8) {\n    Image(systemName: \"sparkles\")\n    Text(\"Dynamic Feature\")\n}",
                availability: "iOS 13.0+"
            ),
            DocSymbol(
                name: "List",
                kind: "struct",
                framework: "SwiftUI",
                summary: "A container that presents rows of data arranged in a single column, optionally supporting section headers, collapsible groups, and editing/deletion row interactions.",
                syntax: "struct List<SelectionValue, Content> : View where SelectionValue : Hashable, Content : View",
                platforms: ["macOS": "10.15", "iOS": "13.0", "tvOS": "13.0"],
                inheritsFrom: nil,
                conformsTo: ["View", "DynamicViewContent"],
                codeSample: "List(items) { item in\n    Text(item.name)\n}",
                availability: "iOS 13.0+"
            ),
            DocSymbol(
                name: "URLSession",
                kind: "class",
                framework: "Foundation",
                summary: "An object that coordinates a group of related, network data-transfer tasks. Instantiates connections across proxies, supporting keep-alive headers, automated session caching, and download-task backgrounding.",
                syntax: "class URLSession : NSObject, Sendable",
                platforms: ["macOS": "10.9", "iOS": "7.0", "watchOS": "2.0", "tvOS": "9.0"],
                inheritsFrom: "NSObject",
                conformsTo: ["Sendable", "NSObjectProtocol"],
                codeSample: "let (data, response) = try await URLSession.shared.data(from: url)\nguard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }",
                availability: "iOS 7.0+"
            ),
            DocSymbol(
                name: "JSONDecoder",
                kind: "class",
                framework: "Foundation",
                summary: "An object that decodes instances of a data type from JSON objects, mapping snake_case or customized API properties seamlessly back to native camelCase Codable Swift properties.",
                syntax: "class JSONDecoder",
                platforms: ["macOS": "10.13", "iOS": "11.0", "watchOS": "4.0", "tvOS": "11.0"],
                inheritsFrom: "NSObject",
                conformsTo: ["NSObjectProtocol"],
                codeSample: "let decoder = JSONDecoder()\ndecoder.keyDecodingStrategy = .convertFromSnakeCase\nlet user = try decoder.decode(User.self, from: data)",
                availability: "iOS 10.0+"
            ),
            DocSymbol(
                name: "NSWindow",
                kind: "class",
                framework: "AppKit",
                summary: "A window that an app displays on the screen, managing the window server interaction, handling close signals, mouse pointer tracking, and split panel layout constraints.",
                syntax: "class NSWindow : NSResponder",
                platforms: ["macOS": "10.0"],
                inheritsFrom: "NSResponder",
                conformsTo: ["NSUserInterfaceValidations", "NSAccessibilityElement", "NSAccessibility"],
                codeSample: "let window = NSWindow(\n    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),\n    styleMask: [.titled, .closable, .resizable],\n    backing: .buffered,\n    defer: false\n)",
                availability: "macOS 10.0+"
            ),
            DocSymbol(
                name: "Task",
                kind: "struct",
                framework: "Swift",
                summary: "A unit of asynchronous work. Enables synchronous actors or classes to spawn isolated asynchronous contexts, configure custom executors, and handle structured cancellation signals.",
                syntax: "struct Task<Success, Failure> : Sendable where Success : Sendable, Failure : Error",
                platforms: ["macOS": "12.0", "iOS": "15.0", "watchOS": "8.0", "tvOS": "15.0"],
                inheritsFrom: nil,
                conformsTo: ["Sendable", "Identifiable"],
                codeSample: "Task {\n    let result = await performNetworkQuery()\n    await updateUI(with: result)\n}",
                availability: "iOS 15.0+"
            ),
            DocSymbol(
                name: "Actor",
                kind: "protocol",
                framework: "Swift",
                summary: "A common protocol that all actors conform to, establishing compiler-enforced thread-isolation requirements to eliminate data races across concurrently running contexts.",
                syntax: "protocol Actor : AnyObject, Sendable",
                platforms: ["macOS": "12.0", "iOS": "15.0", "watchOS": "8.0", "tvOS": "15.0"],
                inheritsFrom: nil,
                conformsTo: ["AnyObject", "Sendable"],
                codeSample: "actor AccountManager {\n    private var balance: Double = 0.0\n    func deposit(amount: Double) { balance += amount }\n}",
                availability: "iOS 15.0+"
            )
        ]
    }
}
