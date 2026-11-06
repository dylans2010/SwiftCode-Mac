import Foundation

/// The project snippet library (Legacy `LibraryCodeSnippet` /
/// `LibrarySnippetCategory` / `LibraryCodeSnippetStore`, Dylan's own code,
/// ported under MIT). Snippets persist as JSON in
/// Application Support/SwiftCode/snippets.json (Legacy used a UserDefaults key).
/// The store seeds the same two snippets Legacy seeded on first launch.
/// Export is a JSON file write, not a `FileDocument`: the SwiftUI shell
/// has no exporter wired to this store yet (see the wiring list).
public struct LibraryCodeSnippet: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var code: String
    public var category: LibrarySnippetCategory
    public var language: String
    public var tags: [String]
    public var usageCount: Int
    public var isFavorite: Bool
    public var isPinned: Bool

    public init(
        id: UUID = UUID(), title: String, code: String,
        category: LibrarySnippetCategory, language: String, tags: [String] = [],
        usageCount: Int = 0, isFavorite: Bool = false, isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.code = code
        self.category = category
        self.language = language
        self.tags = tags
        self.usageCount = usageCount
        self.isFavorite = isFavorite
        self.isPinned = isPinned
    }

    public static let empty = LibraryCodeSnippet(title: "", code: "", category: .utilities, language: "Swift")
}

public enum LibrarySnippetCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case swiftUIViews = "SwiftUI Views"
    case networking = "Networking"
    case asyncTasks = "Async Tasks"
    case dataModels = "Data Models"
    case utilities = "Utilities"
    public var id: String { rawValue }
}

public enum LibraryCodeSnippetStore {
    public static var storeURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("SwiftCode", isDirectory: true).appendingPathComponent("snippets.json")
    }

    public static func load() -> [LibraryCodeSnippet] {
        if let url = storeURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([LibraryCodeSnippet].self, from: data) {
            return decoded
        }
        return [
            LibraryCodeSnippet(
                title: "Async Task MainActor wrapper",
                code: "Task {\n    await MainActor.run {\n        // Update UI state securely\n    }\n}",
                category: .asyncTasks, language: "Swift", tags: ["async", "mainactor"], isPinned: true
            ),
            LibraryCodeSnippet(
                title: "Custom SwiftUI Button Style",
                code: "struct ModernButtonStyle: ButtonStyle {\n    func makeBody(configuration: Configuration) -> some View {\n        configuration.label\n            .padding(.horizontal, 16)\n            .padding(.vertical, 8)\n            .background(Color.accentColor)\n            .cornerRadius(8)\n            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)\n    }\n}",
                category: .swiftUIViews, language: "Swift", tags: ["swiftui", "button"]
            ),
        ]
    }

    public static func save(_ snippets: [LibraryCodeSnippet]) {
        guard let url = storeURL, let data = try? JSONEncoder().encode(snippets) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public static func exportJSON(_ snippets: [LibraryCodeSnippet], to url: URL) throws {
        let data = try JSONEncoder().encode(snippets)
        try data.write(to: url, options: .atomic)
    }

    public static func importJSON(from url: URL) throws -> [LibraryCodeSnippet] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([LibraryCodeSnippet].self, from: data)
    }
}
