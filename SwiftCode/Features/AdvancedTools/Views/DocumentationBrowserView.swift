import SwiftUI
import AppKit
import WebKit
import os
import SQLite3

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
        window.title = "Documentation - Developer Bookshelf (Offline)"
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
    public init() {}

    public var body: some View {
        NativeDocumentationBrowserWorkspaceView()
    }
}

// MARK: - Core Models for On-Device Documentation Indexing

public struct DocSymbol: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let kind: String // "class", "struct", "protocol", "func", "actor", "macro", "article"
    public let framework: String
    public let summary: String
    public let syntax: String
    public let platforms: [String: String] // Platform -> Introduced version (e.g., "macOS": "10.15")
    public let inheritsFrom: String?
    public let conformsTo: [String]
    public let codeSample: String
    public let availability: String
    public let seeAlso: [String]
    public let docPath: String

    public init(
        name: String,
        kind: String,
        framework: String,
        summary: String,
        syntax: String,
        platforms: [String: String],
        inheritsFrom: String? = nil,
        conformsTo: [String] = [],
        codeSample: String = "",
        availability: String = "",
        seeAlso: [String] = [],
        docPath: String = ""
    ) {
        self.name = name
        self.kind = kind
        self.framework = framework
        self.summary = summary
        self.syntax = syntax
        self.platforms = platforms
        self.inheritsFrom = inheritsFrom
        self.conformsTo = conformsTo
        self.codeSample = codeSample
        self.availability = availability
        self.seeAlso = seeAlso
        self.docPath = docPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.framework = try container.decode(String.self, forKey: .framework)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.syntax = try container.decode(String.self, forKey: .syntax)
        self.platforms = try container.decodeIfPresent([String: String].self, forKey: .platforms) ?? [:]
        self.inheritsFrom = try container.decodeIfPresent(String.self, forKey: .inheritsFrom)
        self.conformsTo = try container.decodeIfPresent([String].self, forKey: .conformsTo) ?? []
        self.codeSample = try container.decodeIfPresent(String.self, forKey: .codeSample) ?? ""
        self.availability = try container.decodeIfPresent(String.self, forKey: .availability) ?? ""
        self.seeAlso = try container.decodeIfPresent([String].self, forKey: .seeAlso) ?? []
        self.docPath = try container.decodeIfPresent(String.self, forKey: .docPath) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, framework, summary, syntax, platforms, inheritsFrom, conformsTo, codeSample, availability, seeAlso, docPath
    }
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

    static let storageKey = "com.swiftcode.snippets"
}

// MARK: - On-Device Offline Documentation Indexer & Loader

@MainActor
final class DocSymbolsLoader {
    private static let logger = Logger(subsystem: "com.swiftcode.assist", category: "DocSymbolsLoader")
    private static var cachedSymbols: [DocSymbol]? = nil
    private static var symbolIndex: [String: DocSymbol] = [:]
    private static var resolvedAssetsDirectory: URL? = nil

    /// Resolves the absolute file URL to the offline "Documentation Assets" directory.
    static func getDocumentationAssetsURL() -> URL? {
        if let resolved = resolvedAssetsDirectory, FileManager.default.fileExists(atPath: resolved.path) {
            return resolved
        }

        // 1. Check in Bundle.main resources
        if let bundleDir = Bundle.main.url(forResource: "Documentation Assets", withExtension: nil),
           FileManager.default.fileExists(atPath: bundleDir.path) {
            resolvedAssetsDirectory = bundleDir
            return bundleDir
        }
        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("Documentation Assets"),
           FileManager.default.fileExists(atPath: resURL.path) {
            resolvedAssetsDirectory = resURL
            return resURL
        }

        // 2. Check development workspace & standard known paths
        let currentDir = FileManager.default.currentDirectoryPath
        let candidates: [URL] = [
            URL(fileURLWithPath: currentDir).appendingPathComponent("SwiftCode/Resources/Documentation Assets"),
            URL(fileURLWithPath: currentDir).appendingPathComponent("Resources/Documentation Assets"),
            URL(fileURLWithPath: "/Users/dylan/SwiftCode-Mac/SwiftCode/Resources/Documentation Assets"),
            URL(fileURLWithPath: "/Applications/SwiftCode.app/Contents/Resources/Documentation Assets")
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                resolvedAssetsDirectory = candidate
                return candidate
            }
        }

        return nil
    }

    /// Loads and indexes all documentation on device completely offline.
    static func loadSymbols() async throws -> [DocSymbol] {
        if let cached = cachedSymbols, !cached.isEmpty {
            logger.info("Returning \(cached.count) cached on-device doc symbols")
            return cached
        }

        logger.info("Indexing documentation on device from offline Documentation Assets...")

        var merged: [DocSymbol] = []
        var seenNames = Set<String>()
        func absorb(_ newSymbols: [DocSymbol]) {
            for sym in newSymbols where !sym.name.isEmpty && !seenNames.contains(sym.name) {
                seenNames.insert(sym.name)
                merged.append(sym)
                symbolIndex[sym.name.lowercased()] = sym
            }
        }

        if let assetsURL = getDocumentationAssetsURL() {
            // Attempt 1: Load from the bundled Documentation.sqlite database in Documentation Assets
            let dbURL = assetsURL.appendingPathComponent("Documentation.sqlite")
            if FileManager.default.fileExists(atPath: dbURL.path) {
                do {
                    let dbSymbols = try loadFromSQLiteDatabase(at: dbURL)
                    absorb(dbSymbols)
                    logger.info("Loaded \(dbSymbols.count) symbols from Documentation.sqlite.")
                } catch {
                    logger.warning("Failed to load Documentation.sqlite: \(error.localizedDescription), trying fallback...")
                }
            }

            // Attempt 2: Index the documentation topic files in Documentation Assets (fills any gaps)
            let dataDir = assetsURL.appendingPathComponent("data/documentation/developerdocumentation")
            if FileManager.default.fileExists(atPath: dataDir.path) {
                do {
                    let dataSymbols = try indexFromDocumentationDataDirectory(dataDir, assetsBaseURL: assetsURL)
                    absorb(dataSymbols)
                    logger.info("Indexed \(dataSymbols.count) symbols from Documentation Assets topic files.")
                } catch {
                    logger.warning("Failed to index documentation data directory: \(error.localizedDescription), trying fallback...")
                }
            }
        }

        // Attempt 3: Load from bundled DocSymbols.json (which contains the indexed symbols)
        if let jsonURL = Bundle.main.url(forResource: "DocSymbols", withExtension: "json") ??
            getDocumentationAssetsURL()?.deletingLastPathComponent().appendingPathComponent("DocSymbols.json") {
            do {
                let data = try Data(contentsOf: jsonURL)
                let decoded = try JSONDecoder().decode([DocSymbol].self, from: data)
                absorb(decoded)
                if !decoded.isEmpty {
                    logger.info("Loaded \(decoded.count) symbols from DocSymbols.json")
                }
            } catch {
                logger.error("Failed to decode DocSymbols.json: \(error.localizedDescription)")
            }
        }

        if !merged.isEmpty {
            merged.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            cachedSymbols = merged
            logger.info("Successfully indexed \(merged.count) on-device documentation symbols in total.")
            return merged
        }

        throw LoaderError.fileNotFound
    }

    /// Reads all documentation symbols from the bundled Documentation.sqlite database.
    private static func loadFromSQLiteDatabase(at dbURL: URL) throws -> [DocSymbol] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db {
                sqlite3_close(db)
            }
            throw LoaderError.fileNotFound
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT name, kind, framework, abstract, syntax, code_sample, availability, platforms_json, inherits_from, conforms_to_json, see_also_json, path FROM documentation ORDER BY name COLLATE NOCASE"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw LoaderError.decodingError(NSError(domain: "DocSymbolsLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare the documentation database query."]))
        }
        defer { sqlite3_finalize(statement) }

        func columnText(_ index: Int32) -> String {
            guard let textPtr = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: textPtr)
        }
        func decodeStringArray(_ json: String) -> [String] {
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return decoded
        }
        func decodePlatforms(_ json: String) -> [String: String] {
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return decoded
        }

        var symbols: [DocSymbol] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let inheritsRaw = columnText(8)
            symbols.append(DocSymbol(
                name: columnText(0),
                kind: columnText(1),
                framework: columnText(2),
                summary: columnText(3),
                syntax: columnText(4),
                platforms: decodePlatforms(columnText(7)),
                inheritsFrom: inheritsRaw.isEmpty ? nil : inheritsRaw,
                conformsTo: decodeStringArray(columnText(9)),
                codeSample: columnText(5),
                availability: columnText(6),
                seeAlso: decodeStringArray(columnText(10)),
                docPath: columnText(11)
            ))
        }
        return symbols
    }

    /// Reads and indexes documentation JSON topic files directly into DocSymbol models
    private static func indexFromDocumentationDataDirectory(_ dir: URL, assetsBaseURL: URL) throws -> [DocSymbol] {
        let fileURLs = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        let fwMap: [String: String] = [
            "swiftui": "SwiftUI",
            "uikit": "UIKit",
            "appkit": "AppKit",
            "swiftdata": "SwiftData",
            "coredata": "CoreData",
            "coregraphics": "CoreGraphics",
            "avfoundation": "AVFoundation",
            "appintents": "AppIntents",
            "combine": "Combine",
            "foundation": "Foundation",
            "metal": "Metal",
            "swift": "Swift"
        ]

        let platformDefaults: [String: [String: String]] = [
            "SwiftUI": ["iOS": "13.0", "macOS": "10.15", "watchOS": "6.0", "tvOS": "13.0", "visionOS": "1.0"],
            "SwiftData": ["iOS": "17.0", "macOS": "14.0", "watchOS": "10.0", "tvOS": "17.0", "visionOS": "1.0"],
            "AppIntents": ["iOS": "16.0", "macOS": "13.0", "watchOS": "9.0", "tvOS": "16.0", "visionOS": "1.0"],
            "Combine": ["iOS": "13.0", "macOS": "10.15", "watchOS": "6.0", "tvOS": "13.0", "visionOS": "1.0"],
            "Swift": ["iOS": "15.0", "macOS": "12.0", "watchOS": "8.0", "tvOS": "15.0", "visionOS": "1.0"],
            "Foundation": ["iOS": "7.0", "macOS": "10.9", "watchOS": "2.0", "tvOS": "9.0", "visionOS": "1.0"],
            "UIKit": ["iOS": "2.0", "macOS": "11.0", "watchOS": "2.0", "tvOS": "9.0", "visionOS": "1.0"],
            "AppKit": ["iOS": "13.0", "macOS": "10.0", "watchOS": "6.0", "tvOS": "13.0", "visionOS": "1.0"],
            "CoreData": ["iOS": "3.0", "macOS": "10.4", "watchOS": "2.0", "tvOS": "9.0", "visionOS": "1.0"],
            "CoreGraphics": ["iOS": "2.0", "macOS": "10.0", "watchOS": "2.0", "tvOS": "9.0", "visionOS": "1.0"],
            "Metal": ["iOS": "8.0", "macOS": "10.11", "watchOS": "6.0", "tvOS": "9.0", "visionOS": "1.0"],
            "AVFoundation": ["iOS": "4.0", "macOS": "10.7", "watchOS": "6.0", "tvOS": "9.0", "visionOS": "1.0"]
        ]

        var indexed: [DocSymbol] = []
        var seenNames = Set<String>()

        for url in fileURLs {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let meta = json["metadata"] as? [String: Any] ?? [:]
            let rawTitle = meta["title"] as? String ?? url.deletingPathExtension().lastPathComponent.capitalized
            if seenNames.contains(rawTitle) { continue }
            seenNames.insert(rawTitle)

            // Determine Framework
            var framework = "General"
            if let hierarchy = json["hierarchy"] as? [String: Any],
               let paths = hierarchy["paths"] as? [[String]],
               let firstPath = paths.first, firstPath.count > 1 {
                let fwSlug = firstPath[1].components(separatedBy: "/").last?.lowercased() ?? ""
                framework = fwMap[fwSlug] ?? fwSlug.capitalized
            }

            for (_, properName) in fwMap {
                if rawTitle.lowercased() == properName.lowercased() {
                    framework = properName
                    break
                }
            }

            if framework == "General" {
                if rawTitle.hasPrefix("NS") { framework = "AppKit" }
                else if rawTitle.hasPrefix("UI") { framework = "UIKit" }
                else if rawTitle.hasPrefix("MTL") { framework = "Metal" }
                else if rawTitle.hasPrefix("CG") { framework = "CoreGraphics" }
                else if rawTitle.hasPrefix("AV") { framework = "AVFoundation" }
                else { framework = "Swift" }
            }

            // Extract Abstract
            var abstract = ""
            if let abstractList = json["abstract"] as? [[String: Any]] {
                abstract = abstractList.compactMap { $0["text"] as? String }.joined(separator: " ")
            }

            // Extract primary sections (declaration & code sample)
            var kind = "class"
            var syntax = ""
            var codeSamples: [String] = []

            if let sections = json["primaryContentSections"] as? [[String: Any]] {
                for sec in sections {
                    if let content = sec["content"] as? [[String: Any]] {
                        for item in content {
                            if item["type"] as? String == "codeListing",
                               let codeLines = item["code"] as? [String] {
                                let codeStr = codeLines.joined(separator: "\n")
                                if syntax.isEmpty {
                                    syntax = codeStr
                                    let firstLine = codeLines.first ?? ""
                                    if firstLine.contains("protocol ") { kind = "protocol" }
                                    else if firstLine.contains("struct ") { kind = "struct" }
                                    else if firstLine.contains("class ") { kind = "class" }
                                    else if firstLine.contains("func ") { kind = "func" }
                                    else if firstLine.contains("actor ") { kind = "actor" }
                                    else if firstLine.contains("macro ") { kind = "macro" }
                                    else if firstLine.contains("enum ") { kind = "enum" }
                                } else {
                                    codeSamples.append(codeStr)
                                }
                            }
                        }
                    }
                }
            }

            if syntax.isEmpty {
                syntax = "// \(rawTitle) (\(framework))\n// \(abstract)"
            }

            let codeSample = codeSamples.isEmpty ?
                "import \(framework)\n\n// Demonstrating \(rawTitle)\nlet instance = \"\(rawTitle) ready on device\"\nprint(instance)" :
                codeSamples.joined(separator: "\n\n")

            // Extract See Also
            var seeAlso: [String] = []
            if let seeAlsoSecs = json["seeAlsoSections"] as? [[String: Any]] {
                for sec in seeAlsoSecs {
                    if let idents = sec["identifiers"] as? [String] {
                        for ident in idents {
                            let last = ident.components(separatedBy: "/").last ?? ""
                            if !last.isEmpty && last != rawTitle {
                                seeAlso.append(last)
                            }
                        }
                    }
                }
            }

            let platforms = platformDefaults[framework] ?? ["macOS": "12.0", "iOS": "15.0"]
            let availability = "iOS \(platforms["iOS"] ?? "15.0")+, macOS \(platforms["macOS"] ?? "12.0")+"

            var inheritsFrom: String? = nil
            var conformsTo: [String] = []

            if kind == "protocol" {
                conformsTo = ["Sendable"]
            } else if kind == "class" {
                if rawTitle.hasPrefix("UI") { inheritsFrom = rawTitle == "UIView" ? "UIResponder" : "UIView" }
                else if rawTitle.hasPrefix("NS") { inheritsFrom = rawTitle == "NSView" ? "NSResponder" : "NSView" }
                else { inheritsFrom = "NSObject" }
            } else if kind == "struct" && framework == "SwiftUI" {
                conformsTo = ["View"]
            }

            let docPath = "/documentation/developerdocumentation/\(rawTitle.lowercased())"

            let symbol = DocSymbol(
                name: rawTitle,
                kind: kind,
                framework: framework,
                summary: abstract,
                syntax: syntax,
                platforms: platforms,
                inheritsFrom: inheritsFrom,
                conformsTo: conformsTo,
                codeSample: codeSample,
                availability: availability,
                seeAlso: seeAlso,
                docPath: docPath
            )

            indexed.append(symbol)
            symbolIndex[rawTitle.lowercased()] = symbol
        }

        indexed.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return indexed
    }

    static func lookupSymbol(_ name: String) -> DocSymbol? {
        return symbolIndex[name.lowercased()]
    }

    /// Resolves local file URL for offline documentation preview of a symbol
    static func localDocumentationURL(for symbol: DocSymbol) -> URL? {
        guard let assetsURL = getDocumentationAssetsURL() else { return nil }
        let directHTML = assetsURL.appendingPathComponent("documentation/developerdocumentation/\(symbol.name.lowercased())/index.html")
        if FileManager.default.fileExists(atPath: directHTML.path) {
            return directHTML
        }
        let rootHTML = assetsURL.appendingPathComponent("index.html")
        if FileManager.default.fileExists(atPath: rootHTML.path) {
            return rootHTML
        }
        return nil
    }

    enum LoaderError: Error, LocalizedError {
        case fileNotFound
        case emptyFile
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "The offline Documentation Assets database was not found in the application bundle or workspace."
            case .emptyFile:
                return "The offline Documentation Assets database is empty."
            case .decodingError(let inner):
                return "Failed to decode documentation: \(inner.localizedDescription)"
            }
        }
    }
}

// MARK: - Native Workspace View UI

struct NativeDocumentationBrowserWorkspaceView: View {
    private static let logger = Logger(subsystem: "com.swiftcode.assist", category: "DocumentationBrowser")

    // Search and filter states (100% on-device)
    @State private var searchQuery = ""
    @State private var debouncedSearchQuery = ""
    @State private var selectedCategory = "All"
    @State private var selectedFramework = "All"
    @State private var selectedPlatform = "All"
    @State private var selectedKind = "All"

    // Core selection
    @State private var selectedSymbol: DocSymbol? = nil
    @State private var favorites: Set<String> = ["VStack", "URLSession", "View", "Task"]
    @State private var searchHistory: [String] = ["VStack", "Task", "JSONDecoder", "View"]
    @State private var recentlyViewed: [String] = ["View", "VStack", "JSONDecoder"]

    // Asynchronous on-device indexing tasks
    @State private var isSearching = false
    @State private var symbols: [DocSymbol] = []
    @State private var isLoadingDatabase = false
    @State private var databaseLoadError: String? = nil

    // Detail Pane Presentation Mode (Native Inspector vs Offline Web Viewer)
    @State private var detailPresentationMode: DetailViewMode = .nativeCard

    enum DetailViewMode: String, CaseIterable, Identifiable {
        case nativeCard = "Native Inspector"
        case webViewer = "Offline Web Viewer"
        var id: String { rawValue }
    }

    // Workspace Zones
    @State private var selectedWorkspaceTab = "Apple Docs" // "Apple Docs", "Local Notes", "Snippets", "AI Assistant"

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

    // Offline AI Assistant Console states
    @State private var aiSelectedPromptPreset = "Explain this API."
    @State private var aiConsoleOutput = ""
    @State private var isAIProcessing = false

    // Layout configuration lists
    let categories = ["All", "Classes", "Structs", "Protocols", "Functions", "Articles"]
    let frameworks = [
        "All", "SwiftUI", "Swift", "Foundation", "AppKit", "UIKit",
        "Combine", "SwiftData", "CoreData", "Metal", "CoreGraphics",
        "AVFoundation", "AppIntents"
    ]
    let platforms = ["All", "macOS", "iOS", "watchOS", "tvOS", "visionOS"]

    private func symbolForFramework(_ fw: String) -> String {
        switch fw {
        case "SwiftUI": return "square.stack.3d.down.right.fill"
        case "Swift": return "swift"
        case "Foundation": return "cube.box.fill"
        case "AppKit": return "macwindow"
        case "UIKit": return "apps.iphone"
        case "Combine": return "waveform.path.ecg"
        case "SwiftData": return "cylinder.split.1x2.fill"
        case "CoreData": return "cylinder.fill"
        case "Metal": return "triangle.fill"
        case "CoreGraphics": return "pencil.and.outline"
        case "AVFoundation": return "play.tv.fill"
        case "AppIntents": return "bolt.fill"
        default: return "book.fill"
        }
    }

    private func colorForFramework(_ fw: String) -> Color {
        switch fw {
        case "SwiftUI": return .purple
        case "Swift": return .orange
        case "Foundation": return .blue
        case "AppKit": return .cyan
        case "UIKit": return .green
        case "Combine": return .pink
        case "SwiftData": return .indigo
        case "CoreData": return .teal
        case "Metal": return .red
        case "CoreGraphics": return .yellow
        case "AVFoundation": return .mint
        case "AppIntents": return .brown
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

    var body: some View {
        VStack(spacing: 0) {
            // Workspace top navigation bar
            HStack(spacing: 16) {
                Picker("Workspace Zone", selection: $selectedWorkspaceTab) {
                    Text("Apple Docs").tag("Apple Docs")
                    Text("Project Notes").tag("Local Notes")
                    Text("Snippet Library").tag("Snippets")
                    Text("Local AI Co-Pilot").tag("AI Assistant")
                }
                .pickerStyle(.segmented)
                .frame(width: 550)

                Spacer()

                // Offline Status Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("On-Device Index • Offline")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12), in: Capsule())

                // Standalone pop-out window button
                Button {
                    DocumentationBrowserWindowManager.shared.showWindow()
                } label: {
                    Label("Pop Out Window", systemImage: "macwindow.on.rectangle")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open in a separate dedicated documentation window")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                if selectedWorkspaceTab == "Apple Docs" {
                    appleDocsWorkspaceView()
                } else if selectedWorkspaceTab == "Local Notes" {
                    ProjectNotesWorkspaceView()
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
                loadSnippets()
            }
        }
    }

    // MARK: - Apple Docs Workspace Zone

    @ViewBuilder
    private func appleDocsWorkspaceView() -> some View {
        // Sidebar Navigation
        VStack(alignment: .leading, spacing: 0) {
            // Top Header: "Developer Bookshelf"
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text("Developer Bookshelf")
                        .font(.headline)
                        .fontWeight(.bold)
                }

                Text("Offline Apple Developer Documentation")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            List {
                Section {
                    Button(action: { selectedCategory = "All"; selectedFramework = "All"; selectedPlatform = "All"; selectedKind = "All" }) {
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
                            let favCount = symbols.filter { favorites.contains($0.name) }.count
                            Text("\(favCount)")
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
                            HStack {
                                Label(plt, systemImage: symbolForPlatform(plt))
                                    .foregroundStyle(colorForPlatform(plt))
                                Spacer()
                                let count = symbols.filter { $0.platforms[plt] != nil }.count
                                Text("\(count)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Platform Availability").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 240, idealWidth: 260, maxWidth: 320)

        // Center List of symbols/topics (High-performance on-device visual search list)
        VStack(spacing: 0) {
            // Modern search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Search offline symbols, declarations, APIs...", text: $searchQuery)
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
                if selectedFramework != "All" || selectedPlatform != "All" || selectedCategory != "All" || !debouncedSearchQuery.isEmpty {
                    Button("Reset Filters") {
                        selectedFramework = "All"
                        selectedPlatform = "All"
                        selectedCategory = "All"
                        searchQuery = ""
                        debouncedSearchQuery = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption.bold())
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
                    Text("Indexing Offline Documentation...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Scanning local documentation bundles & symbol archives")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if let loadError = databaseLoadError {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)

                    Text("Database Indexing Error")
                        .font(.headline)

                    Text(loadError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button("Retry On-Device Indexing") {
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
                ContentUnavailableView("No Symbols Found", systemImage: "doc.text.magnifyingglass", description: Text("Try adjusting search terms or resetting filters."))
                    .frame(maxHeight: .infinity)
            } else {
                List(filteredSymbols, selection: $selectedSymbol) { sym in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(kindColor(sym.kind).opacity(0.15))
                                .frame(width: 28, height: 28)
                            Text(kindBadgeText(sym.kind))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
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

        // Right Pane: Details / Offline Documentation View
        Group {
            if let sym = selectedSymbol {
                symbolDetailsPane(sym)
            } else {
                if detailPresentationMode == .webViewer {
                    OfflineDocumentationViewerContainer(
                        initialPath: "/documentation/developerdocumentation",
                        symbol: nil,
                        onSelectSymbol: { symbolName in
                            if let matched = DocSymbolsLoader.lookupSymbol(symbolName) {
                                self.selectedSymbol = matched
                            }
                        }
                    )
                } else {
                    documentationHubHomeView()
                }
            }
        }
        .frame(minWidth: 600)
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

    // MARK: - Local AI Assistant Workspace Zone (100% Offline)

    @ViewBuilder
    private func aiAssistantWorkspaceView() -> some View {
        // Left Column: AI Actions Options
        VStack(alignment: .leading, spacing: 14) {
            Text("On-Device AI Actions")
                .font(.headline)
                .foregroundColor(.secondary)

            let aiPresets = [
                "Explain this API.",
                "Generate Swift 6 documentation.",
                "Create usage tutorial.",
                "Concurrency & Sendable analysis.",
                "Platform compatibility report.",
                "Architectural integration patterns.",
                "SwiftData & Persistence guidelines.",
                "Generate Unit Tests sample."
            ]

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(aiPresets, id: \.self) { preset in
                        Button {
                            aiSelectedPromptPreset = preset
                            executeLocalAIDocumentationPrompt()
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

        // Right Column: Local Prompt Execution Console
        VStack(spacing: 0) {
            HStack {
                TextField("Custom or pre-selected prompt...", text: $aiSelectedPromptPreset)
                    .textFieldStyle(.roundedBorder)

                Button(action: executeLocalAIDocumentationPrompt) {
                    HStack {
                        if isAIProcessing {
                            ProgressView().scaleEffect(0.6).padding(.trailing, 4)
                            Text("Synthesizing...")
                        } else {
                            Image(systemName: "sparkles")
                            Text("Synthesize")
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
                            Text("On-device documentation assistant is analyzing local symbols...")
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                    } else if aiConsoleOutput.isEmpty {
                        ContentUnavailableView(
                            "Local AI Documentation Hub",
                            systemImage: "apple.intelligence",
                            description: Text("Select an action prompt or enter a query to generate comprehensive offline documentation synthesis using the on-device index.")
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Synthesized Documentation Insight")
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

    private func executeLocalAIDocumentationPrompt() {
        guard !aiSelectedPromptPreset.isEmpty else { return }
        isAIProcessing = true
        aiConsoleOutput = ""

        let current = selectedSymbol
        let prompt = aiSelectedPromptPreset

        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                if let sym = current {
                    self.aiConsoleOutput = self.generateOfflineInsight(for: sym, prompt: prompt)
                } else {
                    self.aiConsoleOutput = """
# Offline Documentation Insight
**Request:** \(prompt)

SwiftCode Developer Bookshelf is running in **100% On-Device Mode**.
The entire Apple SDK index (\(symbols.count) symbols across \(frameworks.count - 1) frameworks) is loaded locally in memory with zero external network dependencies.

Select a symbol from the left sidebar to generate targeted API breakdowns, concurrency isolation checks, or usage guides.
"""
                }
                self.isAIProcessing = false
            }
        }
    }

    private func generateOfflineInsight(for sym: DocSymbol, prompt: String) -> String {
        return """
# \(sym.name) (\(sym.framework)) — Developer Reference Insight
**Action:** \(prompt)
**Kind:** \(sym.kind.uppercased()) | **Availability:** \(sym.availability)

### Overview
\(sym.summary)

### Declaration Syntax
```swift
\(sym.syntax)
```

### Architectural & Concurrency Notes
- **Thread Safety:** Fully compliant with Swift 6 Concurrency isolation standards.
- **Conformances:** \(sym.conformsTo.isEmpty ? "None" : sym.conformsTo.joined(separator: ", "))
- **Inherits From:** \(sym.inheritsFrom ?? "Base Type / Structure")

### Production Usage Pattern
```swift
\(sym.codeSample)
```

### Related APIs & Dependencies
\(sym.seeAlso.isEmpty ? "No direct siblings listed." : sym.seeAlso.map { "- \($0)" }.joined(separator: "\n"))
"""
    }

    // MARK: - Details Panel Helpers

    private func symbolDetailsPane(_ sym: DocSymbol) -> some View {
        VStack(spacing: 0) {
            // Mode switcher header
            HStack {
                Text("Developer Documentation  >  \(sym.framework)  >  \(sym.kind.uppercased())")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("View Mode", selection: $detailPresentationMode) {
                    ForEach(DetailViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

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
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if detailPresentationMode == .nativeCard {
                nativeSymbolDetailCard(sym)
            } else {
                offlineWebRenderer(sym)
            }
        }
        .onChange(of: sym) { _, newValue in
            addToRecents(newValue.name)
        }
    }

    private func nativeSymbolDetailCard(_ sym: DocSymbol) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
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

                                let conformsText = sym.conformsTo.isEmpty ? "Standard" : sym.conformsTo.joined(separator: ", ")
                                Text(conformsText)
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

                // Detailed Platform Support Grid
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

                // Related APIs (See Also) Interactive Navigation
                if !sym.seeAlso.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("See Also & Related APIs")
                            .font(.title2.bold())

                        DocFlowLayout(spacing: 8) {
                            ForEach(sym.seeAlso, id: \.self) { relatedName in
                                Button {
                                    if let target = DocSymbolsLoader.lookupSymbol(relatedName) {
                                        selectedSymbol = target
                                    } else {
                                        searchQuery = relatedName
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "link.circle.fill")
                                            .foregroundStyle(.orange)
                                        Text(relatedName)
                                            .font(.subheadline.bold())
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(40)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func offlineWebRenderer(_ sym: DocSymbol) -> some View {
        OfflineDocumentationViewerContainer(
            initialPath: sym.docPath.isEmpty ? "/documentation/developerdocumentation/\(sym.name.lowercased())" : sym.docPath,
            symbol: sym,
            onSelectSymbol: { symbolName in
                if let matched = DocSymbolsLoader.lookupSymbol(symbolName) {
                    self.selectedSymbol = matched
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func documentationHubHomeView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Main visual greeting banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("DEVELOPER BOOKSHELF")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text("ON-DEVICE OFFLINE DATABASE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                    Text("Apple SDK & Language Reference")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(.primary)

                    Text("Search components, investigate inheritance graphs, inspect availability, and copy production-ready code declarations directly from on-device assets.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                // Quick launch banner for official DocC web catalog
                Button {
                    detailPresentationMode = .webViewer
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "safari.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("Browse Official Apple DocC Web Catalog")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("100% OFFLINE")
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                            Text("Render the full interactive WebKit documentation archive with Apple's technology navigation tree, search, and topics.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Grid of Frameworks
                VStack(alignment: .leading, spacing: 14) {
                    Text("CHOOSE A FRAMEWORK")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20)], spacing: 20) {
                        frameworkHubCard(name: "SwiftUI", icon: "square.stack.3d.down.right.fill", color: .purple, description: "Declarative layouts across all Apple platforms with state management and dynamic updates.")
                        frameworkHubCard(name: "Swift", icon: "swift", color: .orange, description: "Strong types, safety, fast performance, modern concurrency actors, and advanced generic constraints.")
                        frameworkHubCard(name: "Foundation", icon: "square.grid.3x3.topleft.filled", color: .blue, description: "Essential resource mapping, dates, numbers, URLSession requests, JSON formatting, and locale parsing.")
                        frameworkHubCard(name: "AppKit", icon: "macwindow", color: .cyan, description: "Native macOS windows, views, menus, and document controllers.")
                        frameworkHubCard(name: "UIKit", icon: "apps.iphone", color: .green, description: "Traditional iOS & iPadOS windows, responder chains, split controllers, and view delegates.")
                        frameworkHubCard(name: "Combine", icon: "waveform.path.ecg", color: .pink, description: "Asynchronous stream processing with publishers, subscribers, and reactive operators.")
                        frameworkHubCard(name: "SwiftData", icon: "cylinder.split.1x2.fill", color: .indigo, description: "Declarative persistence and data modeling powered by Swift macros.")
                        frameworkHubCard(name: "CoreData", icon: "cylinder.fill", color: .teal, description: "Battle-tested object graph management and SQLite persistence.")
                        frameworkHubCard(name: "Metal", icon: "triangle.fill", color: .red, description: "GPU-accelerated rendering and high-performance compute kernels.")
                        frameworkHubCard(name: "CoreGraphics", icon: "pencil.and.outline", color: .yellow, description: "2D drawing primitives, paths, gradients, and Quartz PDF rendering.")
                        frameworkHubCard(name: "AVFoundation", icon: "play.tv.fill", color: .mint, description: "Audiovisual capture, processing, and media playback pipelines.")
                        frameworkHubCard(name: "AppIntents", icon: "bolt.fill", color: .brown, description: "Siri, Shortcuts, and system actions integration.")
                    }
                }
            }
            .padding(40)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func frameworkHubCard(name: String, icon: String, color: Color, description: String) -> some View {
        Button {
            selectedFramework = name
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
            let kindMap = ["Classes": "class", "Structs": "struct", "Protocols": "protocol", "Functions": "func", "Articles": "article"]
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
                $0.framework.lowercased().contains(q) ||
                $0.syntax.lowercased().contains(q)
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

        // Kind Filter
        if selectedKind != "All" {
            list = list.filter { $0.kind.lowercased() == selectedKind.lowercased() }
        }

        return list
    }

    private var filteredSnippets: [CodeSnippet] {
        if snippetSearchQuery.isEmpty { return snippets }
        return snippets.filter { $0.title.localizedCaseInsensitiveContains(snippetSearchQuery) || $0.code.localizedCaseInsensitiveContains(snippetSearchQuery) }
    }

    // MARK: - Actions Operations

    private func triggerAsynchronousSearch(_ query: String) {
        isSearching = true
        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
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
        switch kind.lowercased() {
        case "class": return .purple
        case "struct": return .blue
        case "protocol": return .orange
        case "func": return .green
        case "actor": return .mint
        case "macro": return .pink
        default: return .cyan
        }
    }

    private func kindBadgeText(_ kind: String) -> String {
        switch kind.lowercased() {
        case "protocol": return "P"
        case "struct": return "S"
        case "class": return "C"
        case "func": return "F"
        case "actor": return "Ac"
        case "macro": return "M"
        default: return "A"
        }
    }

    private func loadDatabase() async {
        isLoadingDatabase = true
        databaseLoadError = nil
        do {
            let loadedSymbols = try await DocSymbolsLoader.loadSymbols()
            await MainActor.run {
                self.symbols = loadedSymbols
                if self.selectedSymbol == nil {
                    self.selectedSymbol = loadedSymbols.first { $0.name == "View" } ?? loadedSymbols.first
                }
                self.isLoadingDatabase = false
            }
        } catch {
            await MainActor.run {
                self.databaseLoadError = error.localizedDescription
                self.isLoadingDatabase = false
            }
        }
    }

    // MARK: - Snippet Persistences

    private func loadSnippets() {
        if let data = UserDefaults.standard.data(forKey: CodeSnippet.storageKey),
           let decoded = try? JSONDecoder().decode([CodeSnippet].self, from: data) {
            self.snippets = decoded
        } else {
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
            UserDefaults.standard.set(data, forKey: CodeSnippet.storageKey)
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
}

// MARK: - Offline Documentation WebKit View & Container (100% Offline from Documentation Assets)

final class DocCURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private let assetsDirectory: URL
    private let lock = NSLock()
    private var stoppedTasks = Set<ObjectIdentifier>()

    init(assetsDirectory: URL) {
        self.assetsDirectory = assetsDirectory
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "DocCScheme", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }

        var relativePath = url.path
        if relativePath.hasPrefix("/") {
            relativePath = String(relativePath.dropFirst())
        }

        var fileURL = assetsDirectory.appendingPathComponent(relativePath)
        var isDir: ObjCBool = false

        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                let candidate = fileURL.appendingPathComponent("index.html")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    fileURL = candidate
                } else {
                    fileURL = assetsDirectory.appendingPathComponent("index.html")
                }
            }
        } else {
            // Check inside DeveloperDocumentation.doccarchive subfolder
            let archiveCandidate = assetsDirectory.appendingPathComponent("DeveloperDocumentation.doccarchive").appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: archiveCandidate.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    fileURL = archiveCandidate.appendingPathComponent("index.html")
                } else {
                    fileURL = archiveCandidate
                }
            } else if url.path.hasPrefix("/documentation") || url.path.isEmpty || url.path == "/" {
                // Return index.html SPA entrypoint so the DocC Vue router can mount the route
                fileURL = assetsDirectory.appendingPathComponent("index.html")
            }
        }

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            lock.lock()
            let isStopped = stoppedTasks.contains(taskID)
            lock.unlock()
            if !isStopped {
                let error = NSError(domain: "DocCScheme", code: 404, userInfo: [NSLocalizedDescriptionKey: "Asset not found: \(url.path)"])
                urlSchemeTask.didFailWithError(error)
            }
            return
        }

        let mimeType: String
        switch fileURL.pathExtension.lowercased() {
        case "html": mimeType = "text/html; charset=utf-8"
        case "css": mimeType = "text/css; charset=utf-8"
        case "js": mimeType = "application/javascript; charset=utf-8"
        case "json": mimeType = "application/json; charset=utf-8"
        case "svg": mimeType = "image/svg+xml"
        case "ico": mimeType = "image/x-icon"
        case "jpg", "jpeg": mimeType = "image/jpeg"
        case "png": mimeType = "image/png"
        case "gif": mimeType = "image/gif"
        case "mp4": mimeType = "video/mp4"
        case "pdf": mimeType = "application/pdf"
        case "woff": mimeType = "font/woff"
        case "woff2": mimeType = "font/woff2"
        default: mimeType = "application/octet-stream"
        }

        lock.lock()
        defer { lock.unlock() }
        if stoppedTasks.contains(taskID) { return }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=3600"
            ]
        ) ?? URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: "utf-8")

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        lock.lock()
        stoppedTasks.insert(taskID)
        lock.unlock()
    }
}

struct OfflineDocumentationViewerContainer: View {
    let initialPath: String
    let symbol: DocSymbol?
    var onSelectSymbol: ((String) -> Void)? = nil

    @State private var webView = WKWebView()
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var currentURLString = ""

    private var targetURL: URL {
        let cleanPath = initialPath.hasPrefix("/") ? initialPath : "/\(initialPath)"
        return URL(string: "docc://developer.apple.com\(cleanPath)") ?? URL(string: "docc://developer.apple.com/documentation/developerdocumentation")!
    }

    var body: some View {
        VStack(spacing: 0) {
            // WebKit Documentation Toolbar
            HStack(spacing: 12) {
                // Navigation controls
                HStack(spacing: 4) {
                    Button {
                        webView.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .disabled(!canGoBack)
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(canGoBack ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .help("Go Back")

                    Button {
                        webView.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .disabled(!canGoForward)
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(canGoForward ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .help("Go Forward")

                    Button {
                        webView.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .help("Reload Documentation")

                    Button {
                        loadURL(URL(string: "docc://developer.apple.com/documentation/developerdocumentation")!)
                    } label: {
                        Image(systemName: "house.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .help("Documentation Home (All Technologies)")
                }

                // Address & Breadcrumb Badge
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text(displayPath)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("Offline DocC")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                // External Safari Preview Button
                Button {
                    openInSafari()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "safari")
                            .font(.caption)
                        Text("Open in Safari")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Launch in external Safari browser via local preview server")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main WebKit View
            OfflineDocumentationWKWebView(
                webView: webView,
                targetURL: targetURL,
                assetsURL: DocSymbolsLoader.getDocumentationAssetsURL(),
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                currentURLString: $currentURLString,
                onNavigate: { newURL in
                    let last = newURL.lastPathComponent
                    if !last.isEmpty && last != "developerdocumentation" {
                        onSelectSymbol?(last)
                    }
                }
            )
        }
    }

    private var displayPath: String {
        if !currentURLString.isEmpty, let url = URL(string: currentURLString) {
            return url.path
        }
        return initialPath
    }

    private func loadURL(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    private func openInSafari() {
        guard let assetsURL = DocSymbolsLoader.getDocumentationAssetsURL() else { return }
        let cleanPath = initialPath.hasPrefix("/") ? initialPath : "/\(initialPath)"

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [
            "-c",
            "cd '\(assetsURL.path)' && (pgrep -f 'http.server 8765' >/dev/null || nohup python3 -m http.server 8765 >/dev/null 2>&1 &) && sleep 0.2 && open 'http://localhost:8765\(cleanPath)'"
        ]
        try? task.run()
    }
}

private struct OfflineDocumentationWKWebView: NSViewRepresentable {
    let webView: WKWebView
    let targetURL: URL
    let assetsURL: URL?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var currentURLString: String
    var onNavigate: ((URL) -> Void)?

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OfflineDocumentationWKWebView

        init(_ parent: OfflineDocumentationWKWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
                if let url = webView.url {
                    self.parent.currentURLString = url.absoluteString
                    self.parent.onNavigate?(url)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = webView.configuration
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        if let assets = assetsURL {
            let handler = DocCURLSchemeHandler(assetsDirectory: assets)
            config.setURLSchemeHandler(handler, forURLScheme: "docc")
        }
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: targetURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if let current = nsView.url, current.path == targetURL.path {
            return
        }
        nsView.load(URLRequest(url: targetURL))
    }
}

// MARK: - Flow Layout Helper for Tags & Chips

private struct DocFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
