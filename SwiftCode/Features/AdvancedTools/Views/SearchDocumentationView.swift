import SwiftUI

// MARK: - Models

struct AppleDocSymbol: Identifiable, Hashable, Sendable {
    let id: UUID = UUID()
    let name: String
    let framework: String
    let type: String // "Class", "Struct", "Method", "Property", "Protocol"
    let summary: String
    let urlString: String
}

enum AppleDocFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case frameworks = "Frameworks"
    case symbols = "Symbols"
    case apis = "APIs"

    var id: String { rawValue }
}

// MARK: - ViewModel

@MainActor
final class AppleDocSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedFilter: AppleDocFilter = .all
    @Published var isSearching = false
    @Published var selectedSymbol: AppleDocSymbol? = nil

    // Persistent storage
    @Published var favorites: Set<String> = []
    @Published var recentSearches: [String] = []
    @Published var recentViewed: [String] = []

    private static let favoritesKey = "com.swiftcode.docs.favorites"
    private static let recentsKey = "com.swiftcode.docs.recents"
    private static let viewedKey = "com.swiftcode.docs.viewed"

    init() {
        loadPersistence()
    }

    func toggleFavorite(_ symbolName: String) {
        if favorites.contains(symbolName) {
            favorites.remove(symbolName)
        } else {
            favorites.insert(symbolName)
        }
        savePersistence()
    }

    func addToRecentSearches(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.lowercased() == trimmed.lowercased() }
        recentSearches.insert(trimmed, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
        savePersistence()
    }

    func addToRecentViewed(_ symbolName: String) {
        recentViewed.removeAll { $0 == symbolName }
        recentViewed.insert(symbolName, at: 0)
        recentViewed = Array(recentViewed.prefix(8))
        savePersistence()
    }

    func clearRecents() {
        recentSearches.removeAll()
        savePersistence()
    }

    private func loadPersistence() {
        if let favs = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) {
            favorites = Set(favs)
        }
        recentSearches = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        recentViewed = UserDefaults.standard.stringArray(forKey: Self.viewedKey) ?? []
    }

    private func savePersistence() {
        UserDefaults.standard.set(Array(favorites), forKey: Self.favoritesKey)
        UserDefaults.standard.set(recentSearches, forKey: Self.recentsKey)
        UserDefaults.standard.set(recentViewed, forKey: Self.viewedKey)
    }

    // High fidelity offline database of key symbols
    var offlineDatabase: [AppleDocSymbol] {
        [
            // SwiftUI
            AppleDocSymbol(name: "View", framework: "SwiftUI", type: "Protocol", summary: "A type that represents part of the user interface of an app and provides generators.", urlString: "https://developer.apple.com/documentation/swiftui/view"),
            AppleDocSymbol(name: "State", framework: "SwiftUI", type: "Struct", summary: "A property wrapper type that can read and write a value managed by SwiftUI.", urlString: "https://developer.apple.com/documentation/swiftui/state"),
            AppleDocSymbol(name: "Binding", framework: "SwiftUI", type: "Struct", summary: "A property wrapper type that can read and write a value owned by a source of truth.", urlString: "https://developer.apple.com/documentation/swiftui/binding"),
            AppleDocSymbol(name: "ScrollView", framework: "SwiftUI", type: "Struct", summary: "A scrollable view that displays its content within a customizable scroll container.", urlString: "https://developer.apple.com/documentation/swiftui/scrollview"),
            AppleDocSymbol(name: "VStack", framework: "SwiftUI", type: "Struct", summary: "A view that arranges its subviews in a vertical line.", urlString: "https://developer.apple.com/documentation/swiftui/vstack"),
            AppleDocSymbol(name: "HStack", framework: "SwiftUI", type: "Struct", summary: "A view that arranges its subviews in a horizontal line.", urlString: "https://developer.apple.com/documentation/swiftui/hstack"),
            AppleDocSymbol(name: "NavigationStack", framework: "SwiftUI", type: "Struct", summary: "A view that displays a root view and enables you to push additional views over the root.", urlString: "https://developer.apple.com/documentation/swiftui/navigationstack"),
            AppleDocSymbol(name: "Button", framework: "SwiftUI", type: "Struct", summary: "A control that initiates an action when clicked or tapped.", urlString: "https://developer.apple.com/documentation/swiftui/button"),

            // Swift
            AppleDocSymbol(name: "Task", framework: "Swift", type: "Struct", summary: "A unit of asynchronous work that runs in the background concurrently.", urlString: "https://developer.apple.com/documentation/swift/task"),
            AppleDocSymbol(name: "Actor", framework: "Swift", type: "Protocol", summary: "A reference type that isolates its state to prevent concurrent data races.", urlString: "https://developer.apple.com/documentation/swift/actor"),
            AppleDocSymbol(name: "Sendable", framework: "Swift", type: "Protocol", summary: "A type whose values can be safely transferred across concurrent boundaries.", urlString: "https://developer.apple.com/documentation/swift/sendable"),
            AppleDocSymbol(name: "AsyncSequence", framework: "Swift", type: "Protocol", summary: "A sequence that provides asynchronous, sequential, read-only access to its elements.", urlString: "https://developer.apple.com/documentation/swift/asyncsequence"),

            // Foundation
            AppleDocSymbol(name: "URLSession", framework: "Foundation", type: "Class", summary: "An object that coordinates a group of related, network data-transfer tasks.", urlString: "https://developer.apple.com/documentation/foundation/urlsession"),
            AppleDocSymbol(name: "JSONDecoder", framework: "Foundation", type: "Class", summary: "An object that decodes instances of a data type from JSON objects.", urlString: "https://developer.apple.com/documentation/foundation/jsondecoder"),
            AppleDocSymbol(name: "NSRegularExpression", framework: "Foundation", type: "Class", summary: "An immutable representation of a compiled regular expression pattern.", urlString: "https://developer.apple.com/documentation/foundation/nsregularexpression"),

            // AppKit
            AppleDocSymbol(name: "NSWorkspace", framework: "AppKit", type: "Class", summary: "A workspace that lets you open URLs, apps, and manage finder elements.", urlString: "https://developer.apple.com/documentation/appkit/nsworkspace"),
            AppleDocSymbol(name: "NSPasteboard", framework: "AppKit", type: "Class", summary: "An object that transfers data to and from the system clipboard.", urlString: "https://developer.apple.com/documentation/appkit/nspasteboard"),

            // CoreML
            AppleDocSymbol(name: "MLModel", framework: "CoreML", type: "Class", summary: "An encapsulated machine learning model used for real-time local classification.", urlString: "https://developer.apple.com/documentation/coreml/mlmodel")
        ]
    }

    var filteredResults: [AppleDocSymbol] {
        let lower = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items = offlineDatabase

        if !lower.isEmpty {
            items = items.filter {
                $0.name.lowercased().contains(lower) ||
                $0.framework.lowercased().contains(lower) ||
                $0.summary.lowercased().contains(lower)
            }
        }

        switch selectedFilter {
        case .all:
            return items
        case .frameworks:
            return items.filter { $0.type == "Protocol" || $0.type == "Class" }
        case .symbols:
            return items.filter { $0.type == "Struct" || $0.type == "Protocol" }
        case .apis:
            return items.filter { $0.type == "Method" || $0.type == "Property" }
        }
    }
}

// MARK: - SearchDocumentationView

struct SearchDocumentationView: View {
    @StateObject private var viewModel = AppleDocSearchViewModel()

    var body: some View {
        NavigationSplitView {
            // Left Search sidebar with filter and lists
            VStack(spacing: 0) {

                // Filters Header Card
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search Apple developer documentation...", text: $viewModel.query)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                viewModel.addToRecentSearches(viewModel.query)
                            }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    Picker("Type Filter", selection: $viewModel.selectedFilter) {
                        ForEach(AppleDocFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(14)
                .background(.ultraThinMaterial)

                Divider()

                // Recent Viewed & Recent Searches conditional overview
                if viewModel.query.isEmpty && !viewModel.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Recent Searches")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear") { viewModel.clearRecents() }
                                .font(.caption2)
                                .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(viewModel.recentSearches, id: \.self) { search in
                                    Button(search) {
                                        viewModel.query = search
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    .padding(.bottom, 8)
                    Divider()
                }

                // Symbols List View
                if viewModel.filteredResults.isEmpty {
                    ContentUnavailableView(
                        "No Matches Found",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("No documentation matches for \"\(viewModel.query)\". Try a broader query.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List(viewModel.filteredResults, selection: $viewModel.selectedSymbol) { symbol in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(symbol.name)
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(symbol.framework)
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.orange)
                            }

                            Text(symbol.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                        .tag(symbol)
                        .contextMenu {
                            Button {
                                viewModel.toggleFavorite(symbol.name)
                            } label: {
                                Label(viewModel.favorites.contains(symbol.name) ? "Unfavorite" : "Favorite", systemImage: "star.fill")
                            }

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(symbol.urlString, forType: .string)
                            } label: {
                                Label("Copy Link", systemImage: "doc.on.doc")
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("Documentation Search")
            .frame(minWidth: 260)
        } detail: {
            // Detailed Documentation Preview Pane Card Layout
            if let symbol = viewModel.selectedSymbol {
                ScrollView {
                    VStack(spacing: 24) {

                        // Card 1: Symbol Header
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(symbol.type.uppercased())
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.orange)
                                        Text(symbol.name)
                                            .font(.title2.bold())
                                        Text("Framework: \(symbol.framework)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()

                                    // Favorite Toggle Button
                                    Button {
                                        viewModel.toggleFavorite(symbol.name)
                                    } label: {
                                        Image(systemName: viewModel.favorites.contains(symbol.name) ? "star.fill" : "star")
                                            .font(.title2)
                                            .foregroundStyle(.yellow)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Divider()

                                HStack(spacing: 12) {
                                    Button {
                                        if let url = URL(string: symbol.urlString) {
                                            viewModel.addToRecentViewed(symbol.name)
                                            // Open inside DocumentationBrowserView by posting the notification!
                                            NotificationCenter.default.post(
                                                name: .toolbarToolActivated,
                                                object: nil,
                                                userInfo: ["toolID": "documentation_browser"]
                                            )
                                            // Delay slightly to allow sheet to load and listen
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                NotificationCenter.default.post(
                                                    name: .loadDocURL,
                                                    object: nil,
                                                    userInfo: ["url": url]
                                                )
                                            }
                                        }
                                    } label: {
                                        Label("Open in Documentation Browser", systemImage: "book.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(symbol.urlString, forType: .string)
                                    } label: {
                                        Label("Copy Link", systemImage: "link")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 2: Summary Description
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Overview & Purpose", systemImage: "doc.text.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)

                                Text(symbol.summary)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 3: Live Preview / Declaration
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Developer API Declaration", systemImage: "signature")
                                    .font(.headline)
                                    .foregroundColor(.green)

                                Text("import \(symbol.framework)\n\n// Native declaration link:\n\(symbol.urlString)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.green)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.15))
                                    .cornerRadius(8)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                    .padding(24)
                }
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                ContentUnavailableView(
                    "Search Apple Docs",
                    systemImage: "book.pages",
                    description: Text("Search for frameworks, classes, structs, and methods above to view rich documentation details.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
