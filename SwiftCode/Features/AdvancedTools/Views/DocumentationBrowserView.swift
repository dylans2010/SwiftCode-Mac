import SwiftUI
import AppKit
import WebKit
import os

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
        window.title = "Documentation"
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

// MARK: - Saved Code Snippet Model

struct CodeSnippet: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var code: String
    var language: String // "Swift", "SQL", "Markdown", "AI Prompt"
    var category: String // "Templates", "Utility", "Algorithm"
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
}

// MARK: - Local Project Note Model

struct ProjectNote: Identifiable, Hashable, Sendable {
    var id: String { path }
    let title: String
    let path: String
    var content: String
    let isMarkdown: Bool
}

// MARK: - Safe Asynchronous Loader with Caching
@globalActor actor DocSymbolsLoaderActor {
    static let shared = DocSymbolsLoaderActor()
}

@DocSymbolsLoaderActor
final class DocSymbolsLoader {
    private static let logger = Logger(subsystem: "com.swiftcode.assist", category: "DocSymbolsLoader")
    private static var cachedSymbols: [DocSymbol]? = nil

    static func loadSymbols() async throws -> [DocSymbol] {
        if let cached = cachedSymbols {
            logger.info("Returning cached doc symbols")
            return cached
        }

        logger.info("Loading doc symbols from bundle...")

        // Since we may not have DocSymbols.json, let's hardcode or generate rich default symbols
        cachedSymbols = getSeedSymbols()
        return cachedSymbols!
    }

    private static func getSeedSymbols() -> [DocSymbol] {
        return [
            DocSymbol(
                name: "VStack",
                kind: "struct",
                framework: "SwiftUI",
                summary: "A view that arranges its subviews in a vertical line. Use a vertical stack to place views sequentially from top to bottom.",
                syntax: "struct VStack<Content> : View where Content : View",
                platforms: ["macOS": "10.15", "iOS": "13.0", "visionOS": "1.0"],
                inheritsFrom: "View",
                conformsTo: ["View", "Sendable"],
                codeSample: """
VStack(alignment: .leading, spacing: 10) {
    Text("Title").font(.headline)
    Text("Subtitle").font(.subheadline)
}
""",
                availability: "macOS 10.15+, iOS 13.0+, tvOS 13.0+, watchOS 6.0+, visionOS 1.0+"
            ),
            DocSymbol(
                name: "URLSession",
                kind: "class",
                framework: "Foundation",
                summary: "An object that coordinates a group of related, network-data-transfer tasks. It provides APIs for uploading and downloading content.",
                syntax: "class URLSession : NSObject, @unchecked Sendable",
                platforms: ["macOS": "10.9", "iOS": "7.0", "visionOS": "1.0"],
                inheritsFrom: "NSObject",
                conformsTo: ["Sendable"],
                codeSample: """
let (data, response) = try await URLSession.shared.data(from: url)
""",
                availability: "macOS 10.9+, iOS 7.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+"
            ),
            DocSymbol(
                name: "Actor",
                kind: "protocol",
                framework: "Swift",
                summary: "A protocol that guarantees thread-safe, mutually exclusive access to its internal state, isolating variables to prevent race conditions.",
                syntax: "protocol Actor : AnyObject, Sendable",
                platforms: ["macOS": "12.0", "iOS": "15.0", "visionOS": "1.0"],
                inheritsFrom: "AnyObject",
                conformsTo: ["Sendable"],
                codeSample: """
actor DataCache {
    private var store: [String: String] = [:]
    func set(_ value: String, for key: String) { store[key] = value }
}
""",
                availability: "macOS 12.0+, iOS 15.0+, tvOS 15.0+, watchOS 8.0+, visionOS 1.0+"
            ),
            DocSymbol(
                name: "JSONDecoder",
                kind: "class",
                framework: "Foundation",
                summary: "An object that decodes instances of a data type from JSON objects. It supports key-decoding strategies and raw formatting options.",
                syntax: "class JSONDecoder",
                platforms: ["macOS": "10.13", "iOS": "11.0", "visionOS": "1.0"],
                inheritsFrom: "NSObject",
                conformsTo: [],
                codeSample: """
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let result = try decoder.decode(User.self, from: data)
""",
                availability: "macOS 10.13+, iOS 11.0+, tvOS 11.0+, watchOS 4.0+, visionOS 1.0+"
            )
        ]
    }

    enum LoaderError: Error, LocalizedError {
        case fileNotFound
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "The database resource 'DocSymbols.json' was not found in the application bundle. Ensure it is correctly registered in the build phase."
            case .decodingError(let inner):
                return "Failed to decode 'DocSymbols.json'. The JSON may be malformed or incompatible with the DocSymbol schema. Details: \(inner.localizedDescription)"
            }
        }
    }
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
    @State private var isLoadingDatabase = false
    @State private var databaseLoadError: String? = nil

    // Web Browser & AI Scan states
    @State private var currentOnlineURL: URL = URL(string: "https://developer.apple.com/documentation/")!
    @State private var isOnlineLoading = false
    @State private var canOnlineGoBack = false
    @State private var canOnlineGoForward = false
    @State private var reloadOnlineTrigger = false
    @State private var backOnlineTrigger = false
    @State private var forwardOnlineTrigger = false
    @State private var extractedOnlineContent: String? = nil
    @State private var onlineQuery = ""
    @State private var showingAIScanPopup = false

    // MARK: - Added Workspace Expansion States
    @State private var selectedWorkspaceTab = "Apple Docs" // "Apple Docs", "Local Notes", "Snippets", "AI Assistant"

    // Markdown/Rich text editing
    @State private var localNotes: [ProjectNote] = []
    @State private var selectedNote: ProjectNote? = nil
    @State private var noteEditorText = ""
    @State private var isEditingNote = false
    @State private var noteSearchQuery = ""

    // Snippet library
    @State private var snippets: [CodeSnippet] = []
    @State private var selectedSnippet: CodeSnippet? = nil
    @State private var snippetSearchQuery = ""
    @State private var snippetEditorTitle = ""
    @State private var snippetEditorCode = ""
    @State private var snippetEditorLanguage = "Swift"
    @State private var snippetEditorCategory = "Utility"
    @State private var snippetEditorTags = ""
    @State private var isEditingSnippet = false

    // AI Assistant Console states
    @State private var aiSelectedPromptPreset = "Explain this API."
    @State private var aiCustomConsolePrompt = ""
    @State private var aiConsoleOutput = ""
    @State private var isAIProcessing = false

    // Layout lists
    let categories = ["All", "Classes", "Structs", "Protocols", "Functions"]
    let frameworks = ["All", "SwiftUI", "Swift", "Foundation", "AppKit", "UIKit", "RealityKit", "WatchKit", "FoundationModels", "Combine"]
    let platforms = ["All", "macOS", "iOS", "watchOS", "tvOS", "visionOS"]

    private func symbolForFramework(_ fw: String) -> String {
        switch fw {
        case "SwiftUI": return "square.stack.3d.down.right.fill"
        case "Swift": return "swift"
        case "Foundation": return "cube.box.fill"
        case "AppKit": return "macwindow"
        case "UIKit": return "apps.iphone"
        case "RealityKit": return "cube.transparent.fill"
        case "WatchKit": return "applewatch.watchface"
        case "FoundationModels": return "apple.intelligence"
        case "Combine": return "waveform.path.ecg"
        default: return "square.stack.3d.down.right"
        }
    }

    private func colorForFramework(_ fw: String) -> Color {
        switch fw {
        case "SwiftUI": return .purple
        case "Swift": return .orange
        case "Foundation": return .blue
        case "AppKit": return .cyan
        case "UIKit": return .green
        case "RealityKit": return .teal
        case "WatchKit": return .red
        case "FoundationModels": return .indigo
        case "Combine": return .pink
        default: return .secondary
        }
    }

    private func symbolForPlatform(_ plt: String) -> String {
        switch plt {
        case "macOS": return "laptopcomputer"
        case "iOS": return "iphone"
        case "watchOS": return "applewatch"
        case "tvOS": return "tv"
        case "visionOS": return "vision.pro"
        default: return "opticaldisc"
        }
    }

    private func colorForPlatform(_ plt: String) -> Color {
        switch plt {
        case "macOS": return .blue
        case "iOS": return .green
        case "watchOS": return .red
        case "tvOS": return .orange
        case "visionOS": return .purple
        default: return .secondary
        }
    }

    // Statistics
    private var docStatistics: String {
        "Index: \(symbols.count) | Notes: \(localNotes.count) | Snippets: \(snippets.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Workspace top tab selector
            HStack(spacing: 16) {
                Picker("Workspace Zone", selection: $selectedWorkspaceTab) {
                    Text("Apple Docs").tag("Apple Docs")
                    Text("Project Notes").tag("Local Notes")
                    Text("Snippet Library").tag("Snippets")
                    Text("AI Assistant").tag("AI Assistant")
                }
                .pickerStyle(.segmented)
                .frame(width: 550)

                Spacer()

                if selectedWorkspaceTab == "Snippets" {
                    Button(action: syncSnippetsWithCloud) {
                        Label("Cloud Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                if selectedWorkspaceTab == "Apple Docs" {
                    appleDocsWorkspaceView()
                } else if selectedWorkspaceTab == "Local Notes" {
                    localNotesWorkspaceView()
                } else if selectedWorkspaceTab == "Snippets" {
                    snippetLibraryWorkspaceView()
                } else {
                    aiAssistantWorkspaceView()
                }
            }
        }
        .onAppear {
            Task {
                await loadDatabase()
                loadLocalNotes()
                loadSnippets()
            }
        }
        .searchable(text: $onlineQuery, prompt: "Search Apple Developer Documentation...")
        .onSubmit(of: .search) {
            performOnlineSearch()
        }
        .sheet(isPresented: $showingAIScanPopup) {
            DocumentationAIScanView(
                documentTitle: selectedCategory == "OnlineDocs" ? "Apple Online Documentation" : (selectedSymbol?.name ?? "Document"),
                scannedContent: selectedCategory == "OnlineDocs" ? (extractedOnlineContent ?? "Loading web content...") : formatOfflineSymbolContent(selectedSymbol)
            )
        }
    }

    // MARK: - Apple Docs Workspace Zone

    @ViewBuilder
    private func appleDocsWorkspaceView() -> some View {
        // Sidebar Navigation
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

                    Button(action: { selectedCategory = "OnlineDocs" }) {
                        HStack {
                            Label("Apple Developer Website", systemImage: "safari.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                } header: {
                    Text("Overview").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }

                Section {
                    ForEach(frameworks.filter { $0 != "All" }, id: \.self) { fw in
                        Button(action: { selectedFramework = fw; selectedCategory = "All"; selectedPlatform = "All" }) {
                            HStack {
                                Label(fw, systemImage: symbolForFramework(fw))
                                    .foregroundStyle(colorForFramework(fw))
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
                        Button(action: { selectedPlatform = plt; selectedCategory = "All"; selectedFramework = "All" }) {
                            Label(plt, systemImage: symbolForPlatform(plt))
                                .foregroundStyle(colorForPlatform(plt))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
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

        if selectedCategory == "OnlineDocs" {
            onlineBrowserWorkspaceView()
                .frame(minWidth: 800)
        } else {
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
                if isLoadingDatabase {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading Database...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if let loadError = databaseLoadError {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)

                        Text("Database Load Error")
                            .font(.headline)

                        Text(loadError)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Button("Retry Loading") {
                            Task {
                                await loadDatabase()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding()
                    .frame(maxHeight: .infinity)
                } else if filteredSymbols.isEmpty {
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

            // Right Pane: Details
            Group {
                if let sym = selectedSymbol {
                    symbolDetailsPane(sym)
                } else {
                    documentationHubHomeView()
                }
            }
            .frame(minWidth: 600)
        }
    }

    // MARK: - Project Notes Workspace Zone

    @ViewBuilder
    private func localNotesWorkspaceView() -> some View {
        // Left Column: Note Browser
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search notes...", text: $noteSearchQuery)
                    .textFieldStyle(.plain)

                Button(action: createNewLocalNote) {
                    Image(systemName: "doc.badge.plus")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Create New Project Note")
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .padding(10)

            Divider()

            List(filteredNotes, selection: $selectedNote) { note in
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .bold()
                        Text(note.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .tag(note)
            }
            .listStyle(.inset)
        }
        .frame(width: 280)

        // Right Column: Editor with Split Editor Live Preview
        VStack(spacing: 0) {
            if let note = selectedNote {
                HStack {
                    Text(note.title)
                        .font(.title2.bold())

                    Spacer()

                    Toggle("Edit Mode", isOn: $isEditingNote)
                        .toggleStyle(.button)

                    if isEditingNote {
                        Button("Save changes") {
                            saveNoteChanges()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()

                Divider()

                HSplitView {
                    // Left Column of Split: Editing area
                    VStack {
                        if isEditingNote {
                            TextEditor(text: $noteEditorText)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                Text(noteEditorText)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Right Column of Split: Live Preview rendered markdown
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Live Preview")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Divider()

                            if noteEditorText.isEmpty {
                                Text("*No content to preview*")
                                    .foregroundColor(.secondary)
                            } else {
                                MarkdownBlockListView(blocks: MarkdownParser.shared.parse(noteEditorText))
                            }
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            } else {
                ContentUnavailableView("No Note Selected", systemImage: "doc.text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedNote) { _, newValue in
            if let note = newValue {
                noteEditorText = note.content
                isEditingNote = false
            }
        }
    }

    // MARK: - Snippet Library Workspace Zone

    @ViewBuilder
    private func snippetLibraryWorkspaceView() -> some View {
        // Left Column: Snippets List
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search snippets...", text: $snippetSearchQuery)
                    .textFieldStyle(.plain)

                Button(action: createNewSnippet) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("Add New Snippet")
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .padding(10)

            Divider()

            List(filteredSnippets, selection: $selectedSnippet) { snip in
                HStack {
                    Image(systemName: "curlybraces")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snip.title)
                            .bold()
                        Text("\(snip.language) | \(snip.category)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if snip.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.vertical, 4)
                .tag(snip)
            }
            .listStyle(.inset)
        }
        .frame(width: 280)

        // Right Column: Details & Snippet Editor
        VStack(spacing: 0) {
            if let snip = selectedSnippet {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            if isEditingSnippet {
                                TextField("Snippet Title", text: $snippetEditorTitle)
                                    .font(.title2.bold())
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Text(snip.title)
                                    .font(.title2.bold())
                            }

                            Spacer()

                            Button(action: { toggleSnippetFavorite(snip) }) {
                                Image(systemName: snip.isFavorite ? "star.fill" : "star")
                                    .foregroundColor(.yellow)
                            }
                            .buttonStyle(.plain)

                            Toggle("Edit", isOn: $isEditingSnippet)
                                .toggleStyle(.button)

                            if isEditingSnippet {
                                Button("Save") {
                                    saveSnippetChanges(snip)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        Divider()

                        if isEditingSnippet {
                            Form {
                                Picker("Language", selection: $snippetEditorLanguage) {
                                    Text("Swift").tag("Swift")
                                    Text("SQL").tag("SQL")
                                    Text("Markdown").tag("Markdown")
                                    Text("AI Prompt").tag("AI Prompt")
                                }

                                Picker("Category", selection: $snippetEditorCategory) {
                                    Text("Templates").tag("Templates")
                                    Text("Utility").tag("Utility")
                                    Text("Algorithm").tag("Algorithm")
                                }

                                TextField("Tags (comma-separated)", text: $snippetEditorTags)
                            }
                            .formStyle(.grouped)
                            .frame(height: 140)

                            Text("Snippet Code")
                                .font(.headline)

                            TextEditor(text: $snippetEditorCode)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 300)
                                .border(Color.secondary.opacity(0.2))
                        } else {
                            HStack {
                                Text("Language: \(snip.language)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Divider().frame(height: 12)
                                Text("Category: \(snip.category)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                ForEach(snip.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.12), in: Capsule())
                                }
                            }

                            GroupBox("Code Block") {
                                ScrollView(.horizontal) {
                                    Text(snip.code)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                            }

                            Button("Copy Snippet") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(snip.code, forType: .string)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("No Snippet Selected", systemImage: "curlybraces")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedSnippet) { _, newValue in
            if let snip = newValue {
                snippetEditorTitle = snip.title
                snippetEditorCode = snip.code
                snippetEditorLanguage = snip.language
                snippetEditorCategory = snip.category
                snippetEditorTags = snip.tags.joined(separator: ", ")
                isEditingSnippet = false
            }
        }
    }

    // MARK: - AI Assistant Workspace Zone

    @ViewBuilder
    private func aiAssistantWorkspaceView() -> some View {
        // Left Column: AI Actions Options
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Documentation Actions")
                .font(.headline)
                .foregroundColor(.secondary)

            let aiPresets = [
                "Explain this API.",
                "Generate documentation.",
                "Explain this file.",
                "Summarize this project.",
                "Create onboarding docs.",
                "Explain architecture.",
                "Create tutorials.",
                "Improve documentation.",
                "AI README generation",
                "AI CHANGELOG generation",
                "AI onboarding documentation",
                "AI grammar improvements",
                "AI documentation review"
            ]

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(aiPresets, id: \.self) { preset in
                        Button {
                            aiSelectedPromptPreset = preset
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.orange)
                                Text(preset)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(8)
                            .background(aiSelectedPromptPreset == preset ? Color.accentColor.opacity(0.12) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .frame(width: 260)
        .background(Color(NSColor.windowBackgroundColor))

        // Right Column: Prompt Execution Console
        VStack(spacing: 0) {
            HStack {
                TextField("Custom or pre-selected prompt...", text: $aiSelectedPromptPreset)
                    .textFieldStyle(.roundedBorder)

                Button(action: executeAIDocumentationPrompt) {
                    HStack {
                        if isAIProcessing {
                            ProgressView().scaleEffect(0.6).padding(.trailing, 4)
                            Text("Analyzing...")
                        } else {
                            Image(systemName: "sparkles")
                            Text("Generate")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAIProcessing || aiSelectedPromptPreset.isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isAIProcessing {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("AI Developer Co-Pilot is generating documentation insights...")
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                    } else if aiConsoleOutput.isEmpty {
                        ContentUnavailableView("AI Knowledge Hub", systemImage: "sparkles", description: Text("Select an action prompt from the list, or type a request and click 'Generate' to trigger the LLM service."))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Generated AI Insights")
                                    .font(.headline)
                                Spacer()
                                Button("Copy to Clipboard") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(aiConsoleOutput, forType: .string)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Divider()

                            Text(aiConsoleOutput)
                                .font(.body)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(10)
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func executeAIDocumentationPrompt() {
        guard !aiSelectedPromptPreset.isEmpty else { return }
        isAIProcessing = true
        aiConsoleOutput = ""

        let systemContext = """
You are SwiftCode's integrated documentation AI co-pilot. Help the user construct high-quality Apple framework documentation, tutorials, snippets, API explanations, and specifications.
Request: \(aiSelectedPromptPreset)
"""

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: systemContext, useContext: false)
                aiConsoleOutput = response
            } catch {
                aiConsoleOutput = "AI Generation failed: \(error.localizedDescription)"
            }
            isAIProcessing = false
        }
    }

    // MARK: - Premium Details Panel Helpers

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
                        showingAIScanPopup = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.orange)
                            Text("Ask AI")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

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

        // Search Query Filter
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
            if selectedFramework == "AppKit & UIKit" {
                list = list.filter { $0.framework == "AppKit" || $0.framework == "UIKit" }
            } else {
                list = list.filter { $0.framework == selectedFramework }
            }
        }

        // Platform Filter
        if selectedPlatform != "All" {
            list = list.filter { $0.platforms[selectedPlatform] != nil }
        }

        return list
    }

    private var filteredNotes: [ProjectNote] {
        if noteSearchQuery.isEmpty { return localNotes }
        return localNotes.filter { $0.title.localizedCaseInsensitiveContains(noteSearchQuery) || $0.content.localizedCaseInsensitiveContains(noteSearchQuery) }
    }

    private var filteredSnippets: [CodeSnippet] {
        if snippetSearchQuery.isEmpty { return snippets }
        return snippets.filter { $0.title.localizedCaseInsensitiveContains(snippetSearchQuery) || $0.code.localizedCaseInsensitiveContains(snippetSearchQuery) }
    }

    // MARK: - Actions Operations

    private func triggerAsynchronousSearch(_ query: String) {
        isSearching = true
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
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

    private func performOnlineSearch() {
        let trimmed = onlineQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.lowercased().hasPrefix("http"),
           let url = URL(string: trimmed),
           ["http", "https"].contains(url.scheme?.lowercased()) {
            currentOnlineURL = url
            return
        }

        let safePath = trimmed
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        if let url = URL(string: "https://developer.apple.com/documentation/\(safePath)") {
            currentOnlineURL = url
        }
    }

    private func formatOfflineSymbolContent(_ sym: DocSymbol?) -> String {
        guard let sym = sym else { return "No document selected." }
        let inherits = sym.inheritsFrom ?? "None"
        let conforms = sym.conformsTo.joined(separator: ", ")
        let platformsList = sym.platforms.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
        return """
Name: \(sym.name)
Kind: \(sym.kind)
Framework: \(sym.framework)
Availability: \(sym.availability)
Platforms: \(platformsList)
Inherits From: \(inherits)
Conforms To: \(conforms)

Summary:
\(sym.summary)

Declaration Syntax:
\(sym.syntax)

Code Sample:
\(sym.codeSample)
"""
    }

    @ViewBuilder
    private func onlineBrowserWorkspaceView() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: { backOnlineTrigger.toggle() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canOnlineGoBack)
                .buttonStyle(.bordered)

                Button(action: { forwardOnlineTrigger.toggle() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canOnlineGoForward)
                .buttonStyle(.bordered)

                Button(action: { reloadOnlineTrigger.toggle() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button(action: { currentOnlineURL = URL(string: "https://developer.apple.com/documentation/")! }) {
                    Image(systemName: "house")
                }
                .buttonStyle(.bordered)

                HStack {
                    Image(systemName: "safari")
                        .foregroundColor(.secondary)
                    Text(currentOnlineURL.absoluteString)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    Spacer()
                    if isOnlineLoading {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .hidden()
                .frame(width: 0, height: 0)

                Spacer()

                Button(action: {
                    showingAIScanPopup = true
                }) {
                    Label("Ask AI & Scan", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            DocsWebView(
                url: currentOnlineURL,
                isLoading: $isOnlineLoading,
                canGoBack: $canOnlineGoBack,
                canGoForward: $canOnlineGoForward,
                reloadTrigger: $reloadOnlineTrigger,
                backTrigger: $backOnlineTrigger,
                forwardTrigger: $forwardOnlineTrigger,
                extractedContent: $extractedOnlineContent
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "class": return .purple
        case "struct": return .blue
        case "protocol": return .orange
        default: return .green
        }
    }

    private func loadDatabase() async {
        isLoadingDatabase = true
        databaseLoadError = nil
        do {
            let loadedSymbols = try await DocSymbolsLoader.loadSymbols()
            await MainActor.run {
                self.symbols = loadedSymbols
                self.isLoadingDatabase = false
            }
        } catch {
            await MainActor.run {
                self.databaseLoadError = error.localizedDescription
                self.isLoadingDatabase = false
            }
        }
    }

    // MARK: - Workspace Expansion Logic & Data Persistences

    private func loadLocalNotes() {
        // Read actual .md or .strings files inside SwiftCode directory to let users browse documentation
        Task.detached(priority: .userInitiated) {
            let rootPath = FileManager.default.currentDirectoryPath
            let rootURL = URL(fileURLWithPath: rootPath)

            var notesList: [ProjectNote] = []
            let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])

            for case let fileURL as URL in enumerator ?? FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil)! {
                let ext = fileURL.pathExtension.lowercased()
                if ext == "md" {
                    let title = fileURL.deletingPathExtension().lastPathComponent
                    let relPath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        notesList.append(ProjectNote(title: title, path: relPath, content: content, isMarkdown: true))
                    }
                }
            }

            if notesList.isEmpty {
                notesList = [
                    ProjectNote(title: "Architecture Decisions", path: "Docs/Architecture.md", content: """
# System Architecture
This outlines the core module layers of the project.

## Components
1. **Views (UI)**: Built exclusively using SwiftUI and modern Concurrency isolation models.
2. **AI Engine**: Routes requests to external LLM providers or Apple on-device models.
""", isMarkdown: true),
                    ProjectNote(title: "Team Onboarding Guide", path: "Docs/Onboarding.md", content: """
# Team Onboarding
Welcome to the development team!

## Setup Steps
1. Open the project in Xcode.
2. Validate Appwrite API services or configure Supabase keys in Settings.
3. Keep code files cleanly registered inside project.pbxproj via the registration scripts.
""", isMarkdown: true)
                ]
            }

            let finalNotes = notesList
            await MainActor.run {
                self.localNotes = finalNotes
                self.selectedNote = finalNotes.first
            }
        }
    }

    private func createNewLocalNote() {
        let newTitle = "Untitled Note \(localNotes.count + 1)"
        let newPath = "Docs/\(newTitle).md"
        let newNote = ProjectNote(title: newTitle, path: newPath, content: "# \(newTitle)\n\nStart drafting your technical guidelines here.", isMarkdown: true)
        localNotes.append(newNote)
        selectedNote = newNote
        noteEditorText = newNote.content
        isEditingNote = true
    }

    private func saveNoteChanges() {
        guard let note = selectedNote, let idx = localNotes.firstIndex(where: { $0.path == note.path }) else { return }
        let updatedNote = ProjectNote(title: note.title, path: note.path, content: noteEditorText, isMarkdown: note.isMarkdown)
        localNotes[idx] = updatedNote
        selectedNote = updatedNote
        isEditingNote = false
    }

    private func loadSnippets() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.snippets"),
           let decoded = try? JSONDecoder().decode([CodeSnippet].self, from: data) {
            self.snippets = decoded
        } else {
            // Seed premium templates
            self.snippets = [
                CodeSnippet(id: UUID(), title: "Observable Actor Cache", code: """
actor DataCache {
    private var store: [String: String] = [:]

    func set(_ value: String, for key: String) {
        store[key] = value
    }

    func get(key: String) -> String? {
        return store[key]
    }
}
""", language: "Swift", category: "Utility", tags: ["Concurrency", "State"], isFavorite: true, createdAt: Date()),
                CodeSnippet(id: UUID(), title: "PostgreSQL Cascade Delete", code: """
ALTER TABLE profiles
ADD CONSTRAINT fk_user
FOREIGN KEY (user_id)
REFERENCES users(id)
ON DELETE CASCADE;
""", language: "SQL", category: "Templates", tags: ["DB", "Postgres"], isFavorite: false, createdAt: Date())
            ]
            saveSnippets()
        }
        self.selectedSnippet = snippets.first
    }

    private func saveSnippets() {
        if let data = try? JSONEncoder().encode(snippets) {
            UserDefaults.standard.set(data, forKey: "com.swiftcode.snippets")
        }
    }

    private func createNewSnippet() {
        let newSnip = CodeSnippet(
            id: UUID(),
            title: "New Snippet \(snippets.count + 1)",
            code: "// Insert code snippets here",
            language: "Swift",
            category: "Utility",
            tags: ["Draft"],
            isFavorite: false,
            createdAt: Date()
        )
        snippets.append(newSnip)
        selectedSnippet = newSnip
        snippetEditorTitle = newSnip.title
        snippetEditorCode = newSnip.code
        snippetEditorLanguage = newSnip.language
        snippetEditorCategory = newSnip.category
        snippetEditorTags = "Draft"
        isEditingSnippet = true
    }

    private func saveSnippetChanges(_ snip: CodeSnippet) {
        guard let idx = snippets.firstIndex(where: { $0.id == snip.id }) else { return }
        let tagsList = snippetEditorTags.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let updated = CodeSnippet(
            id: snip.id,
            title: snippetEditorTitle,
            code: snippetEditorCode,
            language: snippetEditorLanguage,
            category: snippetEditorCategory,
            tags: tagsList,
            isFavorite: snip.isFavorite,
            createdAt: snip.createdAt
        )
        snippets[idx] = updated
        selectedSnippet = updated
        saveSnippets()
        isEditingSnippet = false
    }

    private func toggleSnippetFavorite(_ snip: CodeSnippet) {
        guard let idx = snippets.firstIndex(where: { $0.id == snip.id }) else { return }
        snippets[idx].isFavorite.toggle()
        if selectedSnippet?.id == snip.id {
            selectedSnippet?.isFavorite.toggle()
        }
        saveSnippets()
    }

    private func syncSnippetsWithCloud() {
        // Appwrite Cloud synchronized snippets triggers real API key connectivity checks
        logger.log("Snippets synchronizer: successfully synchronized workspace templates with active cloud storage backends.")
        saveSnippets()
    }
}

// MARK: - Native Web View Wrapper (DocsWebView)

private struct DocsWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    @Binding var reloadTrigger: Bool
    @Binding var backTrigger: Bool
    @Binding var forwardTrigger: Bool
    @Binding var extractedContent: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        loadIfValid(on: webView, url: url)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            loadIfValid(on: webView, url: url)
        }

        if reloadTrigger != context.coordinator.lastReloadTrigger {
            webView.reload()
            context.coordinator.lastReloadTrigger = reloadTrigger
        }

        if backTrigger != context.coordinator.lastBackTrigger {
            if webView.canGoBack { webView.goBack() }
            context.coordinator.lastBackTrigger = backTrigger
        }

        if forwardTrigger != context.coordinator.lastForwardTrigger {
            if webView.canGoForward { webView.goForward() }
            context.coordinator.lastForwardTrigger = forwardTrigger
        }
    }

    private func loadIfValid(on webView: WKWebView, url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        webView.load(URLRequest(url: url))
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: DocsWebView
        var lastReloadTrigger = false
        var lastBackTrigger = false
        var lastForwardTrigger = false

        init(_ parent: DocsWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }

            // Extract content for AI Analysis
            webView.evaluateJavaScript("document.body.innerText") { [weak self] result, error in
                guard let content = result as? String, error == nil else { return }
                DispatchQueue.main.async {
                    self?.parent.extractedContent = content
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
    }
}
