import AppKit
import SwiftUI
import SwiftCodeIDECore
import SwiftCodeMCP

// MARK: - Documentation Browser (Wave 19 slice A)
//
// The offline Documentation Browser window content: the 57-topic
// offline cache (fetched live once from the public DocC endpoints,
// served offline afterwards) behind Legacy's workspace shape —
// sidebar navigation, search + filters, web pane or native card,
// Snippet Library and AI Co-Pilot tabs.
//
// Ported from Legacy's `DocumentationBrowserView.swift` (Dylan's
// own code, MIT) into destination style, with the differences the
// spec records: no bundled Documentation Assets tree (dropped —
// Apple resources), no hardcoded `/Users/dylan/…` data-dir fallback,
// no `python3 -m http.server` "Open in Safari" (opens the live
// URL instead), no fake AI tab (real `LLMToolCompletionService`),
// bookmarks/recents/history persisted (Legacy's were session-only
// @State), and the load error rendered (Legacy set
// `databaseLoadError` and never displayed it).
//
// Spec: `specs/ide/wave19-docs.md` §6.

public struct DocumentationBrowserView: View {
    @State private var model = DocumentationBrowserModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            DocumentationBrowserSidebarView(model: model)
        } detail: {
            DocumentationBrowserDetailView(model: model)
        }
        .task { await model.reload() }
    }
}

// MARK: - Model

@MainActor
@Observable
final class DocumentationBrowserModel {
    // Cache state.
    var symbols: [DocSymbol] = []
    var cachedCount = 0
    var failedCount = 0
    var totalCount = DocumentationCatalogue.topics.count
    var lastFetch: Date?
    /// Rendered in the detail (Legacy set this and never showed it).
    var loadError: String?
    var isDownloading = false
    var downloadDone = 0
    var downloadCurrent = ""
    var downloadFailures: [String] = []

    // Navigation.
    var selectedPath = ""
    var historyPaths: [String] = [""]
    var historyIndex = 0
    var recents: [String] = []
    var favorites: Set<String> = []

    // Filters (sidebar flat list).
    var searchText = ""
    var selectedCategory = DocumentationBrowserCategory.all
    var selectedFramework = "All"
    var selectedPlatform = "All"
    var favoritesOnly = false

    // Detail.
    var tab = DocumentationBrowserTab.docs
    var detailMode = DocumentationDetailMode.web

    private enum DefaultsKey {
        static let favorites = "com.swiftcode.documentation.favorites"
        static let history = "com.swiftcode.documentation.history"
        static let recents = "com.swiftcode.documentation.recents"
        static let detailMode = "com.swiftcode.documentation.detailMode"
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.favorites) == nil {
            // Legacy's seeded favorites (first launch only).
            favorites = ["VStack", "URLSession", "View", "Task"]
        } else {
            favorites = Set(defaults.stringArray(forKey: DefaultsKey.favorites) ?? [])
        }
        if let savedHistory = defaults.stringArray(forKey: DefaultsKey.history), !savedHistory.isEmpty {
            historyPaths = savedHistory
            historyIndex = savedHistory.count - 1
            selectedPath = savedHistory[historyIndex]
        }
        recents = defaults.stringArray(forKey: DefaultsKey.recents) ?? []
        if let savedMode = defaults.string(forKey: DefaultsKey.detailMode),
           let mode = DocumentationDetailMode(rawValue: savedMode) {
            detailMode = mode
        }
    }

    var selectedSymbol: DocSymbol? {
        guard !selectedPath.isEmpty else { return nil }
        return symbols.first { $0.docPath == selectedPath }
    }

    /// The web pane's path (no leading slash; "" = home).
    var webPath: String {
        selectedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var isFiltering: Bool {
        !searchText.isEmpty || selectedCategory != .all || selectedFramework != "All"
            || selectedPlatform != "All" || favoritesOnly
    }

    var filteredSymbols: [DocSymbol] {
        // 57 rows: the filter is synchronous (no debounce — Legacy's
        // 80 ms debounce was for a corpus orders of magnitude larger).
        symbols.filter { symbol in
            if favoritesOnly && !favorites.contains(symbol.name) { return false }
            if selectedCategory != .all && symbol.kind != selectedCategory.kindValue { return false }
            if selectedFramework != "All" && symbol.framework != selectedFramework { return false }
            if selectedPlatform != "All" && symbol.platforms[selectedPlatform] == nil { return false }
            guard !searchText.isEmpty else { return true }
            let query = searchText.lowercased()
            return symbol.name.lowercased().contains(query)
                || symbol.summary.lowercased().contains(query)
                || symbol.framework.lowercased().contains(query)
                || symbol.syntax.lowercased().contains(query)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func reload() async {
        let cache = DocumentationCache.shared
        let status = await cache.cacheStatus()
        cachedCount = status.cached
        failedCount = status.failed
        totalCount = status.total
        lastFetch = status.lastFetch
        let loaded = await cache.loadSymbols()
        symbols = loaded
        // The rendered load error: a cached topic whose page file
        // is missing or unparseable, or an unreadable index.
        if let indexURL = await cache.indexURL, FileManager.default.fileExists(atPath: indexURL.path),
           await cache.loadIndex() == nil {
            loadError = "The documentation cache index could not be read. Download the topics again to rebuild it."
        } else if loaded.count < status.cached {
            let missing = status.cached - loaded.count
            loadError = "\(missing) cached topic\(missing == 1 ? "" : "s") could not be read from the cache. Download the topics again to rebuild them."
        } else {
            loadError = nil
        }
    }

    /// Downloads all 57 topics, one at a time, reporting progress.
    /// Failed topics are recorded with their reason and never
    /// invented; a second download retries only the failures (the
    /// cache already holds the rest).
    func downloadAll() {
        guard !isDownloading else { return }
        isDownloading = true
        downloadDone = 0
        downloadCurrent = ""
        downloadFailures = []
        Task {
            do {
                _ = try await DocumentationCache.shared.fetchAll { done, total, topic, result in
                    // The progress closure runs on the main actor
                    // (the fetchAll contract), so model state is
                    // safe to touch directly.
                    self.downloadDone = done
                    self.downloadCurrent = topic.name
                    if !result.cached {
                        self.downloadFailures.append("\(topic.name): \(result.failure ?? "unknown error")")
                    }
                }
            } catch {
                downloadFailures.append(error.localizedDescription)
            }
            await reload()
            isDownloading = false
        }
    }

    /// A navigation (sidebar, hub card, or a link in the web pane).
    /// Records history (truncating any forward branch) and recents.
    func select(path: String) {
        guard path != selectedPath else { return }
        selectedPath = path
        if historyIndex < historyPaths.count - 1 {
            historyPaths.removeSubrange((historyIndex + 1)...)
        }
        historyPaths.append(path)
        if historyPaths.count > 50 { historyPaths.removeFirst() }
        historyIndex = historyPaths.count - 1
        UserDefaults.standard.set(historyPaths, forKey: DefaultsKey.history)
        if !path.isEmpty {
            recents.removeAll { $0 == path }
            recents.insert(path, at: 0)
            if recents.count > 12 { recents.removeLast() }
            UserDefaults.standard.set(recents, forKey: DefaultsKey.recents)
        }
    }

    /// A navigation that came from the web pane itself (a clicked
    /// link). Same as `select`, minus the reload loop: the web
    /// view's coordinator already recorded the URL it loaded.
    func selectFromWeb(path: String) {
        select(path: "/" + path)
    }

    func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        selectedPath = historyPaths[historyIndex]
    }

    func goForward() {
        guard historyIndex < historyPaths.count - 1 else { return }
        historyIndex += 1
        selectedPath = historyPaths[historyIndex]
    }

    func toggleFavorite(_ name: String) {
        if favorites.contains(name) {
            favorites.remove(name)
        } else {
            favorites.insert(name)
        }
        UserDefaults.standard.set(Array(favorites), forKey: DefaultsKey.favorites)
    }

    func setDetailMode(_ mode: DocumentationDetailMode) {
        detailMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.detailMode)
    }

    func openInSafari() {
        guard let symbol = selectedSymbol,
              let url = URL(string: "https://developer.apple.com\(symbol.docPath)") else { return }
        NSWorkspace.shared.open(url)
    }
}

enum DocumentationBrowserTab: String, CaseIterable, Identifiable {
    case docs = "Apple Docs"
    case notes = "Project Notes"
    case snippets = "Snippet Library"
    case ai = "Local AI Co-Pilot"

    var id: String { rawValue }
}

enum DocumentationDetailMode: String {
    case web = "Web"
    case native = "Native"
}

enum DocumentationBrowserCategory: String, CaseIterable {
    case all = "All"
    case classes = "Classes"
    case structs = "Structs"
    case protocols = "Protocols"
    case articles = "Articles"

    var kindValue: String {
        switch self {
        case .all: return ""
        case .classes: return "class"
        case .structs: return "struct"
        case .protocols: return "protocol"
        case .articles: return "article"
        }
    }
}

// MARK: - Sidebar

private struct DocumentationBrowserSidebarView: View {
    @Bindable var model: DocumentationBrowserModel

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search documentation", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            if model.isFiltering {
                filterRow
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.isFiltering {
                        filteredList
                    } else {
                        homeRow
                        if !model.recents.isEmpty {
                            recentsSection
                        }
                        sectionsList
                    }
                }
            }
            downloadFooter
        }
    }

    private var filterRow: some View {
        VStack(spacing: 6) {
            Picker("Kind", selection: $model.selectedCategory) {
                ForEach(DocumentationBrowserCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.menu)
            Picker("Framework", selection: $model.selectedFramework) {
                Text("All Frameworks").tag("All")
                ForEach(DocumentationCatalogue.frameworks, id: \.self) { framework in
                    Text(framework).tag(framework)
                }
            }
            .pickerStyle(.menu)
            Picker("Platform", selection: $model.selectedPlatform) {
                Text("All Platforms").tag("All")
                ForEach(["iOS", "macOS", "watchOS", "tvOS", "visionOS"], id: \.self) { platform in
                    Text(platform).tag(platform)
                }
            }
            .pickerStyle(.menu)
            Toggle("Favorites only", isOn: $model.favoritesOnly)
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var homeRow: some View {
        sidebarButton(title: "Developer Documentation", systemImage: "books.vertical.fill", path: "")
    }

    private var recentsSection: some View {
        DisclosureGroup("Recents") {
            ForEach(model.recents, id: \.self) { path in
                sidebarButton(title: topicName(for: path), systemImage: "clock", path: path)
            }
        }
        .padding(.horizontal, 8)
    }

    private var sectionsList: some View {
        ForEach(DocumentationCatalogue.defaultSections()) { section in
            DisclosureGroup {
                ForEach(section.collections) { collection in
                    DisclosureGroup {
                        ForEach(collection.groups) { group in
                            DisclosureGroup(group.title) {
                                ForEach(group.items) { item in
                                    sidebarButton(title: item.title, systemImage: "doc.text", path: item.path)
                                }
                            }
                            .padding(.leading, 8)
                        }
                    } label: {
                        Label(collection.title, systemImage: collection.icon)
                    }
                    .padding(.leading, 8)
                }
            } label: {
                Label(section.title, systemImage: section.icon)
            }
            .padding(.horizontal, 8)
        }
    }

    private var filteredList: some View {
        ForEach(model.filteredSymbols) { symbol in
            sidebarButton(title: symbol.name, systemImage: "doc.text", path: symbol.docPath, detail: symbol.framework)
        }
        .padding(.horizontal, 8)
    }

    private var downloadFooter: some View {
        VStack(spacing: 6) {
            Divider()
            if model.isDownloading {
                ProgressView(value: Double(model.downloadDone), total: Double(model.totalCount)) {
                    Text("Downloading \(model.downloadCurrent)…")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            } else if model.cachedCount < model.totalCount {
                Button("Download \(model.totalCount) Offline Topics") {
                    model.downloadAll()
                }
                .padding(.vertical, 6)
                Text("\(model.cachedCount) of \(model.totalCount) cached"
                     + (model.failedCount > 0 ? " · \(model.failedCount) failed" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            } else {
                Text("\(model.cachedCount) topics cached offline")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
        }
    }

    private func sidebarButton(title: String, systemImage: String, path: String, detail: String? = nil) -> some View {
        Button {
            model.select(path: path)
        } label: {
            HStack {
                Image(systemName: systemImage).foregroundStyle(.secondary)
                Text(title).lineLimit(1)
                if let detail {
                    Spacer()
                    Text(detail).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(model.selectedPath == path ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func topicName(for path: String) -> String {
        DocumentationCatalogue.topics.first { "/" + $0.docPath == path }?.name
            ?? path.split(separator: "/").last.map(String.init) ?? path
    }
}

// MARK: - Detail

private struct DocumentationBrowserDetailView: View {
    @Bindable var model: DocumentationBrowserModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $model.tab) {
                ForEach(DocumentationBrowserTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)
            switch model.tab {
            case .docs:
                docsTab
            case .notes:
                DocumentationProjectNotesView()
            case .snippets:
                DocumentationSnippetLibraryView()
            case .ai:
                DocumentationAIAssistantView(symbol: model.selectedSymbol)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    model.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(model.historyIndex <= 0)
                Button {
                    model.goForward()
                } label: {
                    Label("Forward", systemImage: "chevron.right")
                }
                .disabled(model.historyIndex >= model.historyPaths.count - 1)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.tab == .docs, model.selectedSymbol != nil {
                    Picker("Detail", selection: $model.detailMode) {
                        Text("Web").tag(DocumentationDetailMode.web)
                        Text("Native").tag(DocumentationDetailMode.native)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.detailMode) { _, mode in model.setDetailMode(mode) }
                    Button {
                        if let symbol = model.selectedSymbol {
                            model.toggleFavorite(symbol.name)
                        }
                    } label: {
                        Label("Favorite",
                              systemImage: model.selectedSymbol.map { model.favorites.contains($0.name) } == true
                                ? "star.fill" : "star")
                    }
                    Button("Open in Safari") { model.openInSafari() }
                }
                if model.cachedCount < model.totalCount && !model.isDownloading {
                    Button("Download") { model.downloadAll() }
                }
            }
        }
    }

    @ViewBuilder
    private var docsTab: some View {
        if let loadError = model.loadError {
            Text(loadError)
                .foregroundStyle(.red)
                .font(.callout)
                .padding(.horizontal)
        }
        if model.selectedSymbol == nil && model.selectedPath.isEmpty {
            DocumentationBrowserHubView(model: model)
        } else if model.detailMode == .native, let symbol = model.selectedSymbol {
            ScrollView {
                DocumentationSymbolDetailView(symbol: symbol, model: model)
            }
        } else {
            DocumentationWebView(docPath: model.webPath) { path in
                Task { @MainActor in model.selectFromWeb(path: path) }
            }
        }
        if model.isDownloading {
            HStack {
                ProgressView(value: Double(model.downloadDone), total: Double(model.totalCount))
                Text("Downloading \(model.downloadCurrent)… (\(model.downloadDone)/\(model.totalCount))")
                    .font(.caption)
            }
            .padding(8)
        }
        if !model.downloadFailures.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Some topics failed to fetch:")
                    .font(.caption).bold()
                ForEach(model.downloadFailures, id: \.self) { failure in
                    Text(failure).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Hub home

private struct DocumentationBrowserHubView: View {
    @Bindable var model: DocumentationBrowserModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Developer Bookshelf")
                        .font(.largeTitle.bold())
                    Text("Apple SDK documentation, cached offline. \(model.cachedCount) of \(model.totalCount) topics cached"
                         + (model.failedCount > 0 ? " (\(model.failedCount) failed to fetch)" : "") + ".")
                        .foregroundStyle(.secondary)
                    if model.cachedCount < model.totalCount {
                        Button(model.isDownloading ? "Downloading…" : "Download All Topics") {
                            model.downloadAll()
                        }
                        .disabled(model.isDownloading)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(DocumentationCatalogue.frameworks, id: \.self) { framework in
                        Button {
                            model.select(path: "/documentation/\(framework.lowercased())")
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(framework).font(.headline)
                                Text(frameworkDescription(framework))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text("\(DocumentationCatalogue.topics.filter { $0.framework == framework }.count) topics")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    private func frameworkDescription(_ framework: String) -> String {
        switch framework {
        case "SwiftUI": return "Declarative UI for Apple platforms."
        case "Swift": return "The Swift language: concurrency, actors, macros."
        case "Foundation": return "Essential types: networking, dates, data, JSON."
        case "AppKit": return "macOS app UI: windows, views, menus."
        case "UIKit": return "iOS app UI: views, view controllers, windows."
        case "Combine": return "Reactive publishers, subscribers, and operators."
        case "SwiftData": return "Modern persistence for Swift models."
        case "CoreData": return "Object graph and persistence framework."
        case "Metal": return "Low-level GPU compute and graphics."
        case "CoreGraphics": return "2D drawing: paths, contexts, transforms."
        case "AVFoundation": return "Audio and video playback and capture."
        case "AppIntents": return "App actions for Shortcuts, Siri, and Spotlight."
        default: return ""
        }
    }
}

// MARK: - Native card

private struct DocumentationSymbolDetailView: View {
    var symbol: DocSymbol
    @Bindable var model: DocumentationBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(symbol.name).font(.largeTitle.bold())
                Text("\(symbol.kind) · \(symbol.framework) · \(symbol.availability)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !symbol.summary.isEmpty {
                Text(symbol.summary)
            }
            if !symbol.syntax.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Declaration").font(.headline)
                    Text(symbol.syntax)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }
            if !symbol.platforms.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Availability").font(.headline)
                    ForEach(symbol.platforms.sorted(by: { $0.key < $1.key }), id: \.key) { platform, version in
                        Text("\(platform) \(version)")
                            .font(.callout)
                    }
                }
            }
            if let inheritsFrom = symbol.inheritsFrom {
                Text("Inherits From: \(inheritsFrom)").font(.callout)
            }
            if !symbol.conformsTo.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conforms To").font(.headline)
                    Text(symbol.conformsTo.joined(separator: ", "))
                        .font(.callout)
                }
            }
            if !symbol.codeSample.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Code Sample").font(.headline)
                    Text(symbol.codeSample)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }
            if !symbol.seeAlso.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("See Also").font(.headline)
                    ForEach(symbol.seeAlso, id: \.self) { related in
                        if let path = DocumentationCatalogue.topics.first(where: { $0.name == related })?.docPath {
                            Button(related) {
                                model.select(path: "/" + path)
                            }
                            .buttonStyle(.link)
                        } else {
                            Text(related).font(.callout)
                        }
                    }
                }
            }
            HStack {
                Button("Open in Safari") { model.openInSafari() }
                Button(model.favorites.contains(symbol.name) ? "Remove from Favorites" : "Add to Favorites") {
                    model.toggleFavorite(symbol.name)
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
